from fastapi import FastAPI
from fastapi.exception_handlers import request_validation_exception_handler
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse

from app.routers import assets, auth, manifests, privacy, profiles, sessions, speakable_page, stories, tts

app = FastAPI(title="Interactive Storybook API", version="0.1.0")
app.include_router(auth.router)
app.include_router(assets.router)
app.include_router(stories.router)
app.include_router(manifests.router)
app.include_router(profiles.router)
app.include_router(sessions.router)
app.include_router(tts.router)
app.include_router(privacy.router)
app.include_router(speakable_page.router)


@app.exception_handler(RequestValidationError)
async def safe_speakable_page_validation_error(request, error):
    if request.url.path.startswith("/v1/speakable-page/"):
        return JSONResponse(
            status_code=422,
            content={"detail": "invalid page request"},
            headers={"Cache-Control": "no-store"},
        )
    return await request_validation_exception_handler(request, error)


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}
