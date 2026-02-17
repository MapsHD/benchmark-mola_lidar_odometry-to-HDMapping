FROM ubuntu:22.04

SHELL ["/bin/bash", "-c"]
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl gnupg lsb-release software-properties-common sudo \
    build-essential git cmake \
    python3-pip \
    nlohmann-json3-dev \
    ca-certificates \
    tmux wget unzip \
    && rm -rf /var/lib/apt/lists/*

RUN curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key \
    | gpg --dearmor -o /usr/share/keyrings/ros-archive-keyring.gpg

RUN echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] \
    http://packages.ros.org/ros2/ubuntu $(lsb_release -cs) main" \
    > /etc/apt/sources.list.d/ros2.list

RUN apt-get update && apt-get install -y --no-install-recommends \
    ros-humble-desktop \
    python3-rosdep \
    python3-colcon-common-extensions \
    python3-vcstool \
    ros-humble-tf2 \
    ros-humble-cv-bridge \
    ros-humble-pcl-conversions \
    ros-humble-pcl-ros \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /ros2_ws

# Copy all source packages (MOLA repos + mola-to-hdmapping converter)
COPY ./src ./src

# Ensure LASzip v3.4.3 with correct headers
RUN git clone --branch 3.4.3 --depth 1 https://github.com/LASzip/LASzip.git /tmp/LASzip && \
    mkdir -p src/mola-to-hdmapping/src/3rdparty/LASzip && \
    cp -rf /tmp/LASzip/* src/mola-to-hdmapping/src/3rdparty/LASzip/ && \
    rm -rf /tmp/LASzip

# Install MOLA dependencies via rosdep
RUN source /opt/ros/humble/setup.bash && \
    apt-get update && \
    rosdep init || true && \
    rosdep update && \
    rosdep install --from-paths src --ignore-src -y && \
    rm -rf /var/lib/apt/lists/*

# Build everything (MOLA + mola-to-hdmapping)
RUN source /opt/ros/humble/setup.bash && \
    colcon build \
        --cmake-args -DCMAKE_BUILD_TYPE=RelWithDebInfo \
        --parallel-workers 2

ARG UID=1000
ARG GID=1000
RUN groupadd -g $GID ros && \
    useradd -m -u $UID -g $GID -s /bin/bash ros

RUN python3 -m pip install "rosbags==0.10.5"

RUN echo "source /opt/ros/humble/setup.bash" >> ~/.bashrc && \
    echo "source /ros2_ws/install/setup.bash" >> ~/.bashrc

CMD ["bash"]
