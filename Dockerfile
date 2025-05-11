FROM ghcr.io/astral-sh/uv:0.7.3 AS uv

# builder
FROM public.ecr.aws/lambda/python:3.13 AS builder
ENV UV_COMPILE_BYTECODE=1 UV_NO_INSTALLER_METADATA=1 UV_LINK_MODE=copy

RUN --mount=from=uv,source=/uv,target=/bin/uv \
    --mount=type=bind,source=pyproject.toml,target=pyproject.toml \
    --mount=type=bind,source=uv.lock,target=uv.lock \
    --mount=type=cache,target=/root/.cache/uv \
    uv pip install -r <(uv export --no-dev --no-emit-workspace) \
        --target "${LAMBDA_TASK_ROOT}"

# runtime
FROM public.ecr.aws/lambda/python:3.13
COPY --from=builder ${LAMBDA_TASK_ROOT} ${LAMBDA_TASK_ROOT}
COPY dashboard ${LAMBDA_TASK_ROOT}/dashboard
COPY handler.py ${LAMBDA_TASK_ROOT}/handler.py
COPY data ${LAMBDA_TASK_ROOT}/data
CMD ["handler.handler"]
