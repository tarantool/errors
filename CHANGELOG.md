# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/en/1.0.0/)
and this project adheres to [Semantic Versioning](http://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [2.2.0] - 2021-05-20

### Added

- New method `errors.netbox_wait_async` - to wait `netbox.fututre`

## [2.1.5] - 2021-03-18

### Fixed

- Enhance error messages of `errors.netbox_call/eval` - supply it with
  the connection URI.

## [2.1.4] - 2020-08-25

### Fixed

- Enhance `errors.pcall()` performance (\~30%) by eliminating
  unnecessary closures creation and `unpack()` which breaks JIT traces.
- Fix building scm-1 version from source.

## [2.1.3] - 2020-03-19

### Added

- Now function `is_error_obj(err)` is a part of public API

### Changed

- Rename netbox error classes to conform the naming conventions:
  "Net.box eval failed" -> "NetboxEvalError",
  "Net.box call failed" -> "NetboxCallError".

## [2.1.2] - 2020-01-17

### Fixed

- Remove duplicate stack trace from `error.str` field

## [2.1.1] - 2019-05-29

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
