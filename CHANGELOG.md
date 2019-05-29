# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/en/1.0.0/)
and this project adheres to [Semantic Versioning](http://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- `errors.new_class` options checking

## [2.1.0] - 2018-05-27

### Fixed

- Use proper `debug.traceback` level for traces

### Added

- Implement `wrap` function for postprocessing net.box call results
- Shortcut functions `errors.new`, `errors.pcall`, `errors.assert`
- Implement API deprecation tools: `errors.deprecate` and `errors.set_deprecation_handler`

## [2.0.1] - 2018-12-20
### Fixed

- Avoid chaining errors
- Rock installation

## [2.0.0] - 2018-11-27
### Added

- Implement `net.box` wrappers
- Ldoc-based API documentation
- Significantly refactor unit tests

### Removed

- Monkey-patching `net.box`

## [1.0.0] - 2018-09-06
### Added

- Basic functionality
- Unit tests
- Luarock-based packaging
- Gitlab CI integration
