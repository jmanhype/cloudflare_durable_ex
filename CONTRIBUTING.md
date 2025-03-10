# Contributing to CloudflareDurable

Thank you for considering contributing to CloudflareDurable! This document outlines the process for contributing to this project.

## Code of Conduct

This project and everyone participating in it is governed by our [Code of Conduct](CODE_OF_CONDUCT.md). By participating, you are expected to uphold this code.

## How Can I Contribute?

### Reporting Bugs

This section guides you through submitting a bug report. Following these guidelines helps maintainers and the community understand your report, reproduce the behavior, and find related reports.

Before creating bug reports, please check the issue list as you might find out that you don't need to create one. When you are creating a bug report, please include as many details as possible:

* **Use a clear and descriptive title** for the issue to identify the problem.
* **Describe the exact steps which reproduce the problem** in as many details as possible.
* **Provide specific examples to demonstrate the steps**. Include links to files or GitHub projects, or copy/pasteable snippets, which you use in those examples.
* **Describe the behavior you observed after following the steps** and point out what exactly is the problem with that behavior.
* **Explain which behavior you expected to see instead and why.**
* **Include screenshots and animated GIFs** which show you following the described steps and clearly demonstrate the problem.
* **If the problem is related to performance or memory**, include a CPU profile capture with your report.
* **If the problem wasn't triggered by a specific action**, describe what you were doing before the problem happened.

### Suggesting Enhancements

This section guides you through submitting an enhancement suggestion, including completely new features and minor improvements to existing functionality.

* **Use a clear and descriptive title** for the issue to identify the suggestion.
* **Provide a step-by-step description of the suggested enhancement** in as many details as possible.
* **Provide specific examples to demonstrate the steps**. Include copy/pasteable snippets which you use in those examples.
* **Describe the current behavior** and **explain which behavior you expected to see instead** and why.
* **Include screenshots and animated GIFs** which help you demonstrate the steps or point out the part of the library which the suggestion is related to.
* **Explain why this enhancement would be useful** to most users.
* **List some other libraries or frameworks where this enhancement exists.**

### Pull Requests

* Fill in the required template
* Follow the Elixir style guides
* Include tests that verify your changes
* Update documentation as needed
* End all files with a newline

## Development Process

### Setting Up a Development Environment

1. Fork and clone the repository
2. Run `mix deps.get` to install dependencies
3. Run `mix test` to ensure everything is working

### Coding Conventions

* We follow the [Elixir Formatting Guidelines](https://hexdocs.pm/mix/main/Mix.Tasks.Format.html)
* Run `mix format` before committing to ensure consistent formatting
* Run `mix credo` to check for code style issues
* Run `mix dialyzer` to perform static analysis

### Testing

* Include tests for all new features or bug fixes
* Run `mix test` to ensure all tests pass
* Aim for high test coverage with `mix coveralls`

### Documentation

* Update module documentation using proper `@doc` and `@moduledoc` attributes
* Keep the README.md up-to-date with changes
* Update the CHANGELOG.md for all notable changes

## Releasing

The release process is managed by maintainers:

1. Update version in `mix.exs`
2. Update `CHANGELOG.md` with the new version
3. Create a new tag for the version
4. Push the tag and GitHub Actions will handle publishing to Hex.pm

## Questions?

Feel free to open an issue with your question or contact the maintainers directly. 