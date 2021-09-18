# syntax = docker/dockerfile:1.2

ARG BUILD_IMAGE=continuumio/miniconda3
ARG PYTHON_VERSION=3.8

FROM ${BUILD_IMAGE} as build

ENV PYTHONUNBUFFERED TRUE

# --mount=type=cache,id=apt-dev,target=/var/cache/apt \

RUN --mount=type=cache,target=/var/cache/apt --mount=type=cache,target=/var/lib/apt \
    apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y \
    ca-certificates \
    build-essential \
    gcc \
    && rm -rf /var/lib/apt/lists/* 

# RUN cd /tmp \
#     && curl -O https://bootstrap.pypa.io/get-pip.py \
#     && python3 get-pip.py

# RUN update-alternatives --install /usr/bin/python python /usr/bin/python3 1
# RUN update-alternatives --install /usr/local/bin/pip pip /usr/local/bin/pip3 1



# RUN useradd -m model-server 
# USER model-server
RUN mkdir /models
WORKDIR /models



RUN --mount=type=cache,target=/opt/conda/pkgs conda create  --name alphapose python=3.6 -y
# Activate new shell with conda env
SHELL ["conda", "run", "-n", "alphapose", "/bin/bash", "-c"]

# The following is from here: https://github.com/MVIG-SJTU/AlphaPose/blob/master/docs/INSTALL.md \
RUN  --mount=type=cache,target=/opt/conda/pkgs --mount=type=cache,target=/root/.cache/pip \
    conda install pytorch-cpu==1.1.0 torchvision-cpu==0.3.0 cpuonly -c pytorch \
    && export PATH=/usr/local/cuda/bin/:$PATH \
    && export LD_LIBRARY_PATH=/usr/local/cuda/lib64/:$LD_LIBRARY_PATH \
    && pip install cython pycocotools \
    && conda install matplotlib \
    && export CUDA_HOME=/usr/local/cuda \
    && export ALPHAPOSE_PATH=/models/AlphaPose \
    # Install conda-pack:
    && conda install -c conda-forge conda-pack \
    # clean up after conda install from https://jcristharif.com/conda-docker-tips.html
    && conda clean -afy 

COPY . AlphaPose/

# Compile alphapose
RUN cd AlphaPose \
    && python3 setup.py build develop --user 

# Use conda-pack to create a standalone enviornment
# in /venv:
RUN conda-pack -n alphapose -o /tmp/env.tar 
RUN mkdir /venv && cd /venv && tar xf /tmp/env.tar && \
    rm /tmp/env.tar

# We've put venv in same path it'll be in final image,
# so now fix up paths:
RUN /venv/bin/conda-unpack

# The runtime-stage image; we can use Debian as the
# base image since the Conda env also includes Python
# for us.
FROM ubuntu:18.04 AS runtime

# Copy /venv from the previous stage:
COPY --from=build /venv /venv

# Copy build from the previous stage:
COPY --from=build /models/AlphaPose/build /inference/AlphaPose/build
COPY alphapose_weights.pth /inference/AlphaPose

# Test Alphapose
# When image is run, run the code with the environment
# activated:
SHELL ["/bin/bash", "-c"]
RUN source /venv/bin/activate && \
    python -c "import numpy; print('success!')"

# Define the default command.
# CMD [ "./run.sh" ]


CMD [ "sleep", "infinity" ]

