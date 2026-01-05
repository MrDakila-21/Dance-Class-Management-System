# Dance-Class-Management-System

An R Shiny application for managing dance studio classes, bookings, and customer information.

## Quick Start with Docker

The easiest way to run this application is using Docker:

```bash
docker-compose up -d
```

Access the application at: http://localhost:3838/dance-studio/

For detailed Docker instructions, see [DOCKER_SETUP.md](DOCKER_SETUP.md)

## Project Structure

- `FinalProjectDraft.R` - Main R Shiny application
- `dance_studio.sql` - MySQL database schema and initial data
- `Dockerfile` - Container image for the Shiny app
- `docker-compose.yml` - Multi-container orchestration
- `DOCKER_SETUP.md` - Detailed Docker setup guide