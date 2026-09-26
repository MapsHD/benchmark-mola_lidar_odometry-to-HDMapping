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

# MOLA comes prebuilt from the ROS 2 Humble apt repository. Building the
# pinned MOLA sources in src/ stopped working once apt moved MRPT on (MRPT
# 2.15.21 changed its point-field API and mp2p_icp 2.6.0 no longer compiles);
# the apt packages are always built against the MRPT that apt installs, so
# they cannot drift apart. This benchmarks the current MOLA release (3.2.0 at
# the time of writing) rather than the pinned sources. The launch file used by
# docker_session_run-ros2-mola.sh, its arguments and the lidar_odometry topics
# are unchanged. Two runtime pieces are not pulled in by the MOLA packages, so
# they are installed explicitly: diagnostic_aggregator, started by that launch
# file, and mola_metric_maps, whose libmola_metric_maps.so the pipeline YAML
# loads as a plugin by name for its local map (mola::KeyframePointCloudMap);
# without it the odometry aborts on the first scan with "Could not find
# 'libmola_metric_maps.so' anywhere under the LD_LIBRARY_PATH paths".
RUN apt-get update && apt-get install -y --no-install-recommends \
    ros-humble-mola-lidar-odometry \
    ros-humble-mola-metric-maps \
    ros-humble-diagnostic-aggregator \
    && rm -rf /var/lib/apt/lists/* && \
    test -f /opt/ros/humble/lib/x86_64-linux-gnu/libmola_metric_maps.so && \
    dpkg-query -W -f='MOLA from apt: ${Package} ${Version}\n' \
        ros-humble-mola-lidar-odometry ros-humble-mola-metric-maps

WORKDIR /ros2_ws

# Only the HDMapping converter is built from source.
COPY ./src/mola-to-hdmapping ./src/mola-to-hdmapping

# Ensure LASzip v3.4.3 with correct headers
RUN git clone --branch 3.4.3 --depth 1 https://github.com/LASzip/LASzip.git /tmp/LASzip && \
    mkdir -p src/mola-to-hdmapping/src/3rdparty/LASzip && \
    cp -rf /tmp/LASzip/* src/mola-to-hdmapping/src/3rdparty/LASzip/ && \
    rm -rf /tmp/LASzip

# Install the converter's dependencies via rosdep
RUN source /opt/ros/humble/setup.bash && \
    apt-get update && \
    rosdep init || true && \
    rosdep update && \
    rosdep install --from-paths src --ignore-src -y && \
    rm -rf /var/lib/apt/lists/*

# Build the converter (mola-to-hdmapping)
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
