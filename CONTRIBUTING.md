# Contributing to MySQL CDC Pipeline

Thank you for your interest in contributing! This document provides guidelines for contributing to this project.

## How to Contribute

### Reporting Bugs

1. Check existing issues to avoid duplicates
2. Use the bug report template
3. Include:
   - Steps to reproduce
   - Expected vs actual behavior
   - Docker/OS versions
   - Relevant logs

### Suggesting Features

1. Open an issue with the feature request template
2. Describe the use case
3. Explain why this would benefit the project

### Pull Requests

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes
4. Test thoroughly
5. Commit with clear messages (`git commit -m 'Add amazing feature'`)
6. Push to your branch (`git push origin feature/amazing-feature`)
7. Open a Pull Request

## Development Setup

```bash
# Clone your fork
git clone https://github.com/yourusername/mysql-cdc-debezium-starrocks.git
cd mysql-cdc-debezium-starrocks

# Start the environment
docker-compose up -d

# Run tests
./test-pipeline.sh
```

## Code Style

### Shell Scripts

- Use `#!/bin/bash` shebang
- Add `set -e` for error handling
- Use meaningful variable names
- Add comments for complex logic
- Quote variables: `"$VAR"` not `$VAR`

### Docker Compose

- Use specific image versions when possible
- Add comments for non-obvious configurations
- Group related environment variables

### SQL

- Use uppercase for SQL keywords
- Use meaningful table and column names
- Add comments for complex queries

## Testing

Before submitting a PR:

1. Start fresh environment:
   ```bash
   docker-compose down -v
   docker-compose up -d
   ```

2. Run setup scripts:
   ```bash
   ./register-debezium.sh
   ./create-starrocks-tables.sh
   ./create-routine-load.sh
   ```

3. Test CDC pipeline:
   ```bash
   ./test-pipeline.sh
   ```

4. Run benchmarks:
   ```bash
   ./benchmark.sh
   ```

## Commit Messages

Follow conventional commits:

- `feat:` New feature
- `fix:` Bug fix
- `docs:` Documentation changes
- `refactor:` Code refactoring
- `test:` Adding tests
- `chore:` Maintenance tasks

Example: `feat: add support for multiple source databases`

## Questions?

Open an issue with the question label or reach out to maintainers.
