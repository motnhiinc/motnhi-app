from fastapi import FastAPI

from app.routers import assets, auth, manifests, privacy, profiles, sessions, stories, tts

app = FastAPI(title="Interactive Storybook API", version="0.1.0")
app.include_router(auth.router)
app.include_router(assets.router)
app.include_router(stories.router)
app.include_router(manifests.router)
app.include_router(profiles.router)
app.include_router(sessions.router)
app.include_router(tts.router)
app.include_router(privacy.router)


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}
