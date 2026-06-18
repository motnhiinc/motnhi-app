from fastapi import FastAPI

from app.routers import auth, profiles, sessions, stories

app = FastAPI(title="Interactive Storybook API", version="0.1.0")
app.include_router(auth.router)
app.include_router(stories.router)
app.include_router(profiles.router)
app.include_router(sessions.router)


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}
