FROM ghcr.io/astral-sh/uv:0.7.3 AS uv

# builder
FROM public.ecr.aws/lambda/python:3.13 AS builder
ENV UV_COMPILE_BYTECODE=1 UV_NO_INSTALLER_METADATA=1 UV_LINK_MODE=copy

WORKDIR /tmp/build

# Mount pyproject.toml and uv.lock to temporary locations
RUN --mount=from=uv,source=/uv,target=/bin/uv \
    --mount=type=cache,target=/root/.cache/uv \
    --mount=type=bind,source=uv.lock,target=/tmp/uv.lock \
    --mount=type=bind,source=pyproject.toml,target=/tmp/pyproject.toml \
    # Copy to build directory (ensuring it's writable)
    cp /tmp/pyproject.toml /tmp/uv.lock . && \
    uv export --frozen --no-emit-workspace --no-dev --no-editable -o requirements.txt && \
    uv pip install -r requirements.txt --target /tmp/build

# runtime
FROM public.ecr.aws/lambda/python:3.13
COPY --from=builder /tmp/build ${LAMBDA_TASK_ROOT}
COPY dashboard ${LAMBDA_TASK_ROOT}/dashboard
COPY handler.py ${LAMBDA_TASK_ROOT}/handler.py
COPY data ${LAMBDA_TASK_ROOT}/data
CMD ["handler.handler"]
