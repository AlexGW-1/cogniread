FROM python:3.11-slim
WORKDIR /app
COPY pyproject.toml ./pyproject.toml
RUN pip install --no-cache-dir -U pip && pip install --no-cache-dir fastapi uvicorn[standard] python-dotenv pydantic
COPY app ./app
EXPOSE 8090
CMD ["uvicorn","app.main:app","--host","0.0.0.0","--port","8090"]
