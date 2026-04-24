FROM node:22-slim

# Core dev tools (tmux and nvim installed separately for newer versions)
RUN apt-get update && apt-get install -y --no-install-recommends \
    git curl wget ripgrep fd-find fzf \
    sudo gosu less jq unzip \
    python3 python3-venv build-essential \
    openssh-client ca-certificates socat \
    ruby-full locales \
    libevent-dev libncurses-dev bison pkg-config \
    && gem install tmuxinator --no-document \
    && sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen \
    && rm -rf /var/lib/apt/lists/*

# tmux 3.5a from source (match Mac version)
RUN cd /tmp \
    && curl -LO https://github.com/tmux/tmux/releases/download/3.5a/tmux-3.5a.tar.gz \
    && tar xzf tmux-3.5a.tar.gz \
    && cd tmux-3.5a \
    && ./configure && make -j$(nproc) && make install \
    && cd / && rm -rf /tmp/tmux-*

# Neovim latest stable (appimage → extract, works on aarch64 and x86_64)
RUN ARCH=$(uname -m) && \
    if [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then \
      curl -LO https://github.com/neovim/neovim/releases/download/v0.11.1/nvim-linux-arm64.tar.gz && \
      tar xzf nvim-linux-arm64.tar.gz && \
      cp -r nvim-linux-arm64/* /usr/local/ && \
      rm -rf nvim-linux-arm64*; \
    else \
      curl -LO https://github.com/neovim/neovim/releases/download/v0.11.1/nvim-linux-x86_64.tar.gz && \
      tar xzf nvim-linux-x86_64.tar.gz && \
      cp -r nvim-linux-x86_64/* /usr/local/ && \
      rm -rf nvim-linux-x86_64*; \
    fi

ENV LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

# uv — fast Python package manager
RUN curl -LsSf https://astral.sh/uv/install.sh | sh \
    && mv /root/.local/bin/uv /usr/local/bin/uv \
    && mv /root/.local/bin/uvx /usr/local/bin/uvx

# Agent user
RUN useradd -m -s /bin/bash agent

# Secrets directory
RUN mkdir -p /etc/devbox && chown root:root /etc/devbox

# Shared scripts
COPY shared/scripts/run /usr/local/bin/run
COPY shared/scripts/lock-env /usr/local/bin/lock-env
COPY shared/scripts/unlock-env /usr/local/bin/unlock-env
RUN chmod 755 /usr/local/bin/run /usr/local/bin/lock-env /usr/local/bin/unlock-env

# Sudoers — agent can ONLY use 'run'
COPY shared/sudoers.d/agent /etc/sudoers.d/agent
RUN chmod 440 /etc/sudoers.d/agent

# Pi extensions and skills (global, for agent user)
RUN mkdir -p /home/agent/.pi/agent/extensions /home/agent/.pi/agent/skills
COPY agents/pi/extensions/ /home/agent/.pi/agent/extensions/
COPY agents/pi/skills/ /home/agent/.pi/agent/skills/

# Nvim data dirs (config is mounted ro, plugins need writable dirs)
RUN mkdir -p /home/agent/.local/share/nvim /home/agent/.local/state/nvim /home/agent/.cache/nvim

# gpakosz/.tmux (latest version, baked into image)
RUN git clone https://github.com/gpakosz/.tmux.git /home/agent/.tmux \
    && ln -sf /home/agent/.tmux/.tmux.conf /home/agent/.tmux.conf

# Tmuxinator config (agent only — tmux runs as agent)
RUN mkdir -p /home/agent/.config/tmuxinator
COPY shared/tmuxinator/dev.yml /home/agent/.config/tmuxinator/dev.yml

# Agent shell config
RUN mkdir -p /home/agent/.local/bin \
    && { \
      echo 'alias pi="node /workspace/pi-mono/packages/coding-agent/dist/cli.js"'; \
      echo 'export PATH="/home/agent/.local/bin:/usr/local/bin:$PATH"'; \
      echo 'export TERM=xterm-256color'; \
    } >> /home/agent/.bashrc

RUN chown -R agent:agent /home/agent

# Entrypoint: locks .env files, builds pi if needed, drops to agent
COPY hosts/docker-mac/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod 755 /usr/local/bin/entrypoint.sh

WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["bash"]
