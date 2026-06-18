from fastapi import FastAPI

app = FastAPI(title="Interactive Storybook API", version="0.1.0")


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}
