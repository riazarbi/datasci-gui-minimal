FROM riazarbi/datasci-base:20240301103343

LABEL authors="Riaz Arbi,Gordon Inggs"

# Be explicit about user
# This is because we switch users during this build and it can get confusing
USER root

# ARGS =======================================================================

# Install R and RStudio
# Works
ENV RSTUDIO_VERSION=2022.02.1-461
#https://s3.amazonaws.com/rstudio-ide-build/server/bionic/amd64/rstudio-server-1.4.1722-amd64.deb
ENV SHINY_VERSION=1.5.9.923
ENV RSESSION_PROXY_RSTUDIO_1_4=yes
#ENV RSESSION_PROXY_WWW_ROOT_PATH='/rstudio/'

# Create same user as jupyter docker stacks so that k8s will run fine
ARG NB_USER="jovyan"
ARG NB_UID="1000"
ARG NB_GID="100"

# Configure environment
# Do we need this? Conflicts early locale settings
ENV SHELL=/bin/bash 
ENV NB_USER=$NB_USER
ENV NB_UID=$NB_UID 
ENV NB_GID=$NB_GID 
ENV LC_ALL=en_US.UTF-8 
ENV LANG=en_US.UTF-8 
ENV LANGUAGE=en_US.UTF-8 
ENV TZ="Africa/Johannesburg" 
ENV HOME=/home/$NB_USER 
ENV JUPYTER_ENABLE_LAB=1 
ENV R_LIBS_SITE=/usr/local/lib/R/site-library

# JUPYTER =====================================================================

# Expose the right port
EXPOSE 8888

# Add a script that we will use to correct permissions after running certain commands
ADD fix-permissions /usr/local/bin/fix-permissions  
RUN chmod +x /usr/local/bin/fix-permissions 

RUN DEBIAN_FRONTEND=noninteractive \ 
    apt-get update \
 && DEBIAN_FRONTEND=noninteractive \
    apt-get install -yq --no-install-recommends \
    npm nodejs \
    libfribidi-dev \
# Install all the jupyter packages
 && python3 -m pip install --upgrade pip && \
    python3 -m pip install jupyter jupyterhub jupyterlab jupyter-rsession-proxy \
 && python3 -m pip install nbgitpuller \
# Enable prompt color in the skeleton .bashrc before creating the default NB_USER
 && sed -i 's/^#force_color_prompt=yes/force_color_prompt=yes/' /etc/skel/.bashrc \
# Create NB_USER with name jovyan user with UID=1000 and in the 'users' group
# and make sure these dirs are writable by the `users` group.
 && echo "auth requisite pam_deny.so" >> /etc/pam.d/su && \
    sed -i.bak -e 's/^%admin/#%admin/' /etc/sudoers && \
    sed -i.bak -e 's/^%sudo/#%sudo/' /etc/sudoers && \
    useradd -m -s /bin/bash -N -u $NB_UID $NB_USER && \
    usermod -a -G staff $NB_USER && \
    chmod g+w /etc/passwd  \
 && /usr/local/bin/fix-permissions $HOME \
 && rm -rf /tmp/*

# RSESSION ==================================================================

# Add apt gpg key
RUN apt-get update -qq \
# install two helper packages we need
 && apt-get install -y --no-install-recommends software-properties-common dirmngr \
# add the signing key (by Michael Rutter) for these repos
# To verify key, run gpg --show-keys /etc/apt/trusted.gpg.d/cran_ubuntu_key.asc 
# Fingerprint: E298A3A825C0D65DFD57CBB651716619E084DAB9
 && wget -qO- https://cloud.r-project.org/bin/linux/ubuntu/marutter_pubkey.asc | sudo tee -a /etc/apt/trusted.gpg.d/cran_ubuntu_key.asc \
# add the R 4.0 repo from CRAN -- adjust 'focal' to 'groovy' or 'bionic' as needed
 && sudo add-apt-repository "deb https://cloud.r-project.org/bin/linux/ubuntu $(lsb_release -cs)-cran40/" \
 && apt-get install -y --no-install-recommends r-base

RUN apt-get install -y gdebi-core \
 && wget --quiet https://download2.rstudio.org/server/focal/amd64/rstudio-server-2023.12.1-402-amd64.deb \
 && gdebi -n rstudio-server-2023.12.1-402-amd64.deb \
 && rm rstudio-server-2023.12.1-402-amd64.deb

# Maybe not needed?
#RUN DEBIAN_FRONTEND=noninteractive \
#    apt-get update && \
#    apt-get install -y --no-install-recommends \
#    libxml2-dev \
#    libssh2-1-dev \
#    libgit2-dev \
#    libcurl4-openssl-dev \
#    cargo \
#    libmagick++-dev \
#    libfontconfig1-dev \
#    libharfbuzz-dev \
#    libfribidi-dev \
#    libgdal-dev \
# && apt-get clean \
# && rm -rf /var/lib/apt/lists/* 

# Install system dependencies
COPY apt.txt .
RUN echo "Checking for 'apt.txt'..." \
        ; if test -f "apt.txt" ; then \
        apt-get update --fix-missing > /dev/null\
        && xargs -a apt.txt apt-get install --yes \
        && apt-get clean > /dev/null \
        && rm -rf /var/lib/apt/lists/* \
        && rm -rf /tmp/* \
        ; fi

# Install R dependencies
COPY install.R .
RUN if [ -f install.R ]; then R --quiet -f install.R; fi


# INSTALL VSCODE ===========================================================

# Install VSCode
RUN curl -fsSL https://code-server.dev/install.sh | sh \
 && pip3 install jupyter-vscode-proxy 

# Install VSCode extensions
RUN code-server --install-extension ms-python.python \
 && code-server --install-extension innoverio.vscode-dbt-power-user \
 && code-server --install-extension REditorSupport.r


# USER SETTINGS ============================================================

# Switch to $NB_USER
RUN /usr/local/bin/fix-permissions $HOME
USER $NB_UID

# Switch to $HOME of $NB_USER
WORKDIR $HOME

# Set NB_USER ENV vars
ENV PATH="${PATH}:/usr/lib/rstudio-server/bin" 
ENV TZ="Africa/Johannesburg"

# Clean npm cache, create a new jupyter notebook config
RUN npm cache clean --force  \
 && jupyter notebook --generate-config  \
 && rm -rf /home/$NB_USER/.cache/yarn 

# Configure container startup
CMD ["/bin/bash", "start-notebook.sh"]

# Add local files as late as possible to avoid cache busting
COPY start.sh /usr/local/bin/
COPY start-notebook.sh /usr/local/bin/
COPY start-singleuser.sh /usr/local/bin/
COPY jupyter_notebook_config.py /etc/jupyter/

# Fix permissions on /etc/jupyter as root
USER root
RUN /usr/local/bin/fix-permissions /etc/jupyter/
RUN /usr/local/bin/fix-permissions $HOME ${JULIA_PKGDIR}

# Run as NB_USER ============================================================

USER $NB_USER
