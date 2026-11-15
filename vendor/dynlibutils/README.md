## DynLibUtils

DynLibUtils is a cross-platform C++ library for interacting with dynamically loaded modules (DLL / SO / DYLIB).
It provides utilities for memory inspection, pattern scanning, section parsing, and virtual table manipulation.

Designed primarily for CS2 server-side development.
Supports Windows, Linux and macOS (x86_64).

---

## Features

* Module introspection (base address, size, sections)
* Pattern scanning (AOB / signature search) with hook-resilient disk-byte scanning
* Virtual table utilities (vtable resolving by name)
* Cross-platform abstraction layer
* Lightweight and dependency-free

---

## Project Structure

```
include/dynlibutils/
├── macros.h
├── memaddr.hpp
├── module.hpp
├── virtual.hpp
└── vthook.hpp

src/
├── module.cpp
├── windows/module.cpp
├── linux/module.cpp
└── apple/module.cpp
```

---

## Building as a static library

### CMake

```sh
cmake -B build
cmake --build build
```

To consume from a parent project:

```cmake
add_subdirectory(vendor/dynlibutils)
target_link_libraries(your_target PRIVATE dynlibutils)
```

### AMBuild

```sh
mkdir build && cd build
python ../configure.py
ambuild
```

The entry point is `AMBuildScript` (picked up automatically by AMBuild).

To consume from a parent project's `AMBuilder`, include the sources directly:

```python
binary.sources += [
    os.path.join('vendor', 'dynlibutils', 'src', 'module.cpp'),
]

binary.compiler.cxxincludes += [
    os.path.join(builder.sourcePath, 'vendor', 'dynlibutils', 'include'),
]
```

---

## Usage Example

```cpp
#include <dynlibutils/module.hpp>

using namespace DynLibUtils;

// Load a module by name
CModule mod("server");

// Find a function by pattern (compile-time parsed)
CMemory pFunc = mod.FindPattern(ParseStringPattern("48 8B ?? ?? ?? 48 85 C0"));

// Find all occurrences with a callback
auto sig = mod.CreateSignature(ParseStringPattern("48 8B ?? ?? ?? 48 85 C0"));
mod.FindAllPatterns(sig, [](std::size_t index, CMemory match) -> bool {
    // return false to stop, true to continue
    return true;
});

// Resolve a vtable by class name
CMemory pVTable = mod.GetVirtualTableByName("SomeClass");

// The table of a base that is not the first one (a secondary vtable):
// by base class name, its position read out of the RTTI...
CMemory pInterfaceVTable = mod.GetVirtualTableByBase("SomeClass", "ISomeInterface");
// ...or by the sub-object's byte offset, which moves with the class layout
CMemory pSecondVTable = mod.GetVirtualTableByOffset("SomeClass", 32);

// Look up an exported function by name
CMemory pExport = mod.GetFunctionByName("SomeExportedFunction");

// Query a section
const Section_t* pSection = mod.GetSectionByName(".text");
```

---

## Notes

* Platform implementations are separated under `src/<platform>/`
* `src/module.cpp` is the shared abstraction layer
* Designed for x86_64 only
* Pattern scanning supports wildcards (`?` or `??`)
* `FindPattern` scans original disk bytes for executable sections rather than live memory — patterns match correctly even if another plugin has already hooked the function and overwritten its prologue with a JMP
