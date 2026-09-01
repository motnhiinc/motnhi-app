from datetime import datetime, timezone
from pathlib import Path

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, delete
from sqlalchemy.orm import sessionmaker

from app.config import settings
from app.db import Base, get_db
from app.main import app as fastapi_app
from app.models import User
import app.models  # noqa: F401

engine = create_engine(settings.test_database_url, future=True)
TestingSessionLocal = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)


@pytest.fixture(scope="session", autouse=True)
def _schema():
    Base.metadata.drop_all(engine)
    Base.metadata.create_all(engine)
    yield
    Base.metadata.drop_all(engine)


@pytest.fixture
def db():
    connection = engine.connect()
    trans = connection.begin()
    session = TestingSessionLocal(bind=connection)
    yield session
    session.close()
    trans.rollback()
    connection.close()


@pytest.fixture
def independent_session_factory():
    opened = []
    committed_user_ids = set()

    def create_session(*, user_id=None):
        connection = engine.connect()
        session = TestingSessionLocal(bind=connection)
        opened.append((session, connection))
        if user_id is not None:
            now = datetime.now(timezone.utc)
            session.add(User(
                id=user_id,
                email=None,
                auth_provider="device",
                created_at=now,
                updated_at=now,
            ))
            session.commit()
            committed_user_ids.add(user_id)
        return session

    yield create_session

    for session, connection in reversed(opened):
        session.rollback()
        session.close()
        connection.close()
    if committed_user_ids:
        with engine.begin() as connection:
            connection.execute(delete(User).where(User.id.in_(committed_user_ids)))


@pytest.fixture
def client(db):
    fastapi_app.dependency_overrides[get_db] = lambda: db
    with TestClient(fastapi_app) as c:
        yield c
    fastapi_app.dependency_overrides.clear()


@pytest.fixture
def seeded(db):
    from seed import seed_all
    data_dir = Path(__file__).resolve().parent.parent.parent / "assets" / "data"
    seed_all(db, data_dir)
    return db
