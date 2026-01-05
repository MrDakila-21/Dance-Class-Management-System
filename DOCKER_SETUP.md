# Docker Setup Guide for Dance Class Management System

This guide explains how to run the Dance Class Management System using Docker.

## Prerequisites

- Docker installed on your system ([Get Docker](https://docs.docker.com/get-docker/))
- Docker Compose installed ([Get Docker Compose](https://docs.docker.com/compose/install/))

## Quick Start

### Using Docker Compose (Recommended)

The easiest way to run the application with all dependencies:

```bash
# Start the application and database
docker-compose up -d

# View logs
docker-compose logs -f

# Stop the application
docker-compose down

# Stop and remove volumes (removes all data)
docker-compose down -v
```

The application will be available at: **http://localhost:3838/dance-studio/**

### Using Docker Only

If you want to build and run the application container separately:

```bash
# Build the Docker image
docker build -t dance-studio-app .

# Run with an external MySQL database
docker run -d \
  -p 3838:3838 \
  -e DB_HOST=your-db-host \
  -e DB_PORT=3306 \
  -e DB_NAME=dance_studio \
  -e DB_USER=root \
  -e DB_PASSWORD=your-password \
  --name dance-studio \
  dance-studio-app
```

## Configuration

### Environment Variables

The application supports the following environment variables for database configuration:

- `DB_HOST` - Database host (default: `127.0.0.1`, Docker Compose: `db`)
- `DB_PORT` - Database port (default: `3306`)
- `DB_NAME` - Database name (default: `dance_studio`)
- `DB_USER` - Database user (default: `root`)
- `DB_PASSWORD` - Database password (default: empty)

### Docker Compose Configuration

The `docker-compose.yml` file includes:

- **MySQL Database**: Runs on port 3306
  - Automatically initializes the database using `dance_studio.sql`
  - Data persists in a Docker volume named `mysql_data`
  
- **Shiny Application**: Runs on port 3838
  - Automatically connects to the MySQL container
  - Waits for the database to be healthy before starting

## File Structure

```
.
├── Dockerfile              # Docker image definition for the R Shiny app
├── docker-compose.yml      # Multi-container orchestration
├── .dockerignore          # Files to exclude from Docker build
├── FinalProjectDraft.R    # Main R Shiny application
├── dance_studio.sql       # Database initialization script
└── DOCKER_SETUP.md        # This file
```

## Troubleshooting

### Application won't start
- Check if ports 3306 and 3838 are already in use
- View logs: `docker-compose logs app`
- Check database status: `docker-compose logs db`

### Database connection errors
- Ensure the database container is healthy: `docker-compose ps`
- Check if the database initialized properly: `docker-compose logs db`
- Verify environment variables in `docker-compose.yml`

### Reset everything
```bash
# Stop containers and remove volumes
docker-compose down -v

# Remove images
docker-compose down --rmi all

# Start fresh
docker-compose up -d
```

## Development

### Rebuilding after code changes

```bash
# Rebuild and restart the app container
docker-compose up -d --build app
```

### Accessing the database directly

```bash
# Connect to MySQL from host
mysql -h 127.0.0.1 -u root -prootpassword dance_studio

# Or use Docker exec
docker-compose exec db mysql -u root -prootpassword dance_studio
```

## Production Considerations

For production deployment, consider:

1. **Change default passwords** in `docker-compose.yml`
2. **Use secrets management** instead of environment variables
3. **Configure reverse proxy** (nginx/Apache) for SSL/TLS
4. **Set up backup strategy** for the MySQL volume
5. **Configure resource limits** for containers
6. **Use production-grade Shiny Server** settings

## Additional Information

- The application runs on **Shiny Server** (not RStudio Connect)
- MySQL data persists in a Docker volume between restarts
- The database is automatically initialized on first run
- Camera features (QR code scanning) require HTTPS in production browsers
