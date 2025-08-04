# Contributing to LibreChat CDK

First off, thank you for considering contributing to LibreChat CDK! It's people like you that make this project possible.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [How Can I Contribute?](#how-can-i-contribute)
- [Development Process](#development-process)
- [Pull Request Process](#pull-request-process)
- [Style Guide](#style-guide)
- [Commit Messages](#commit-messages)

## Code of Conduct

This project and everyone participating in it is governed by our [Code of Conduct](CODE_OF_CONDUCT.md). By participating, you are expected to uphold this code.

## How Can I Contribute?

### Reporting Bugs

Before creating bug reports, please check existing issues as you might find out that you don't need to create one. When you are creating a bug report, please include as many details as possible:

- **Use a clear and descriptive title**
- **Describe the exact steps to reproduce the problem**
- **Provide specific examples to demonstrate the steps**
- **Describe the behavior you observed and explain why it's a problem**
- **Explain which behavior you expected to see instead**
- **Include logs and error messages**
- **Include your environment details** (OS, Node.js version, AWS region, etc.)

### Suggesting Enhancements

Enhancement suggestions are tracked as GitHub issues. When creating an enhancement suggestion, please include:

- **Use a clear and descriptive title**
- **Provide a detailed description of the suggested enhancement**
- **Provide specific examples to demonstrate the feature**
- **Describe the current behavior and explain why it's insufficient**
- **Explain why this enhancement would be useful**

### Pull Requests

- Fill in the required template
- Do not include issue numbers in the PR title
- Follow the [TypeScript](#typescript-style-guide) styleguide
- Include thoughtfully-worded, well-structured tests
- Document new code
- End all files with a newline

## Development Process

1. **Fork the repository** and create your branch from `main`
2. **Install dependencies**:
   ```bash
   npm install
   ```
3. **Make your changes** and ensure:
   - Code compiles without errors: `npm run build`
   - Tests pass: `npm test`
   - Linting passes: `npm run lint`
   - Code is formatted: `npm run format`
4. **Test your changes** in a real AWS environment if possible
5. **Write or update tests** as needed
6. **Update documentation** if you're changing functionality

### Local Development

```bash
# Install dependencies
npm install

# Build the project
npm run build

# Run tests
npm test

# Run tests with coverage
npm run test:coverage

# Lint code
npm run lint

# Format code
npm run format

# Synthesize CDK for validation
npm run synth
```

## Pull Request Process

1. **Ensure all tests pass** and the build is successful
2. **Update the README.md** with details of changes if applicable
3. **Update the CHANGELOG.md** if one exists
4. **Request review** from maintainers
5. **Address review feedback** promptly
6. Your PR will be merged once you have the sign-off of at least one maintainer

### PR Title Format

Use conventional commit format for PR titles:

- `feat:` New feature
- `fix:` Bug fix
- `docs:` Documentation only changes
- `style:` Code style changes (formatting, etc)
- `refactor:` Code refactoring
- `test:` Adding or updating tests
- `chore:` Maintenance tasks

Example: `feat: add support for Aurora Serverless v2`

## Style Guide

### TypeScript Style Guide

We use ESLint and Prettier for code formatting. Run `npm run lint` and `npm run format` before committing.

Key conventions:
- Use TypeScript strict mode
- Prefer `const` over `let`
- Use meaningful variable names
- Add JSDoc comments for public APIs
- Keep functions small and focused
- Use async/await over promises when possible

### CDK Best Practices

- Use L2 constructs when available
- Create reusable constructs for common patterns
- Follow AWS CDK best practices
- Use meaningful construct IDs
- Implement proper tagging strategies
- Consider cost implications of resources

### Documentation Style

- Use clear, concise language
- Include code examples where helpful
- Keep README focused on getting started
- Put detailed guides in the `docs/` directory
- Update relevant documentation with your changes

## Commit Messages

We follow the [Conventional Commits](https://www.conventionalcommits.org/) specification:

```
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]
```

### Examples

```
feat: add EKS deployment option

- Add new EKS construct for container orchestration
- Support both managed and self-managed node groups
- Include example configurations

Closes #123
```

```
fix: correct security group rules for RDS

The previous rules were too permissive. This change restricts
database access to only the application security group.
```

### Types

- **feat**: New feature
- **fix**: Bug fix
- **docs**: Documentation changes
- **style**: Code style changes
- **refactor**: Code refactoring
- **test**: Test changes
- **chore**: Build process or auxiliary tool changes

## Questions?

Feel free to open an issue with your question or reach out to the maintainers.

Thank you for contributing! 🎉