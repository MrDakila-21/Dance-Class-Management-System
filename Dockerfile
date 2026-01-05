# Base image with R and Shiny
FROM rocker/shiny:4.3.1

# Install system dependencies for some packages
RUN apt-get update && apt-get install -y \
    libpng-dev \
    libssl-dev \
    libcurl4-openssl-dev \
    libxml2-dev \
    libv8-dev \
    && rm -rf /var/lib/apt/lists/*

# Install all required R packages
RUN R -e "install.packages(c('shiny','shinyjs','DBI','RSQLite','pool','dplyr','DT','qrcode','png','jsonlite','base64enc'), repos='https://cloud.r-project.org')"

# Copy your app files to Shiny Server folder
COPY . /srv/shiny-server/

# Give proper permissions
RUN chmod -R 755 /srv/shiny-server

# Expose Shiny port
EXPOSE 3838

# Run Shiny Server
CMD ["/usr/bin/shiny-server"]
