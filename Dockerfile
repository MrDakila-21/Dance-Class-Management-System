# Use the rocker/shiny image as base (includes R and Shiny Server)
FROM rocker/shiny:4.3.2

# Install system dependencies for R packages
RUN apt-get update && apt-get install -y \
    libmariadb-dev \
    libmariadb-dev-compat \
    libcurl4-openssl-dev \
    libssl-dev \
    libxml2-dev \
    libpng-dev \
    && rm -rf /var/lib/apt/lists/*

# Install required R packages
RUN R -e "install.packages(c('shiny', 'shinyjs', 'DBI', 'RMySQL', 'pool', 'dplyr', 'DT', 'qrcode', 'png', 'jsonlite', 'base64enc'), repos='https://cran.rstudio.com/')"

# Create app directory
RUN mkdir -p /srv/shiny-server/dance-studio

# Copy application files
COPY FinalProjectDraft.R /srv/shiny-server/dance-studio/app.R

# Set permissions
RUN chown -R shiny:shiny /srv/shiny-server/dance-studio

# Expose Shiny Server port
EXPOSE 3838

# Run Shiny Server
CMD ["/usr/bin/shiny-server"]
