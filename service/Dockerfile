# ---- build stage (dependency validation only — pure stdlib app) ----
FROM python:3.12.7-slim AS build
WORKDIR /app
COPY app.py .
# Compile to bytecode to catch syntax errors early
RUN python -m py_compile app.py

# ---- runtime stage ----
FROM python:3.12.7-slim AS runtime
LABEL maintainer="mohan"

RUN groupadd -r appuser && useradd -r -g appuser -d /app -s /sbin/nologin appuser

WORKDIR /app
COPY --from=build /app/app.py .

USER appuser
EXPOSE 8080

ENTRYPOINT ["python", "app.py"]
