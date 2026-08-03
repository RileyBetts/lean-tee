#!/usr/bin/env python3
"""Apply LEAN_SP1 stubs onto a Lean 4.32.1 src/runtime tree (Anoma LEAN_RISC0 pattern).

Does not copy Anoma 4.22 IO/ST world-arg APIs. Idempotent: skips if already patched.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path


MARK = "LEAN_SP1"


def once(path: Path, needle: str, replacer) -> bool:
    text = path.read_text()
    if f"defined({MARK})" in text or f"ifndef {MARK}" in text or f"ifdef {MARK}" in text:
        # Already has some SP1 guards — still allow specific missing patches via markers
        pass
    new = replacer(text)
    if new == text:
        return False
    path.write_text(new)
    print(f"patched {path}")
    return True


def patch_thread_h(text: str) -> str:
    # Drop adopt_lock_t ctor (needs <mutex>; breaks -fno-exceptions freestanding builds).
    old_ul = """template<typename T> class unique_lock {
public:
    unique_lock(T const &) {}
    unique_lock(T const &, std::adopt_lock_t) {}
    ~unique_lock() {}
    void lock() {}
    void unlock() {}
    T * release() { return nullptr; }
};"""
    new_ul = """template<typename T> class unique_lock {
public:
    unique_lock(T const &) {}
    ~unique_lock() {}
    void lock() {}
    void unlock() {}
    T * release() { return nullptr; }
};"""
    if old_ul in text:
        text = text.replace(old_ul, new_ul, 1)

    if f"defined({MARK})" in text and "LEAN_THREAD_PTR(T, V) static T * V" in text:
        return text
    old = """#ifdef _MSC_VER
#define LEAN_THREAD_PTR(T, V) static __declspec(thread) T * V = nullptr
#define LEAN_THREAD_EXTERN_PTR(T, V) extern __declspec(thread) T * V
#define LEAN_THREAD_GLOBAL_PTR(T, V) __declspec(thread) T * V = nullptr
#define LEAN_THREAD_VALUE(T, V, VAL) static __declspec(thread) T V = VAL
#else
#define LEAN_THREAD_PTR(T, V) static __thread T * V = nullptr
#define LEAN_THREAD_EXTERN_PTR(T, V) extern __thread T * V
#define LEAN_THREAD_GLOBAL_PTR(T, V) __thread T * V = nullptr
#define LEAN_THREAD_VALUE(T, V, VAL) static __thread T V = VAL
#endif"""
    new = f"""#if defined({MARK})
#define LEAN_THREAD_PTR(T, V) static T * V = nullptr
#define LEAN_THREAD_EXTERN_PTR(T, V) extern T * V
#define LEAN_THREAD_GLOBAL_PTR(T, V) T * V = nullptr
#define LEAN_THREAD_VALUE(T, V, VAL) static T V = VAL
#elif defined(_MSC_VER)
#define LEAN_THREAD_PTR(T, V) static __declspec(thread) T * V = nullptr
#define LEAN_THREAD_EXTERN_PTR(T, V) extern __declspec(thread) T * V
#define LEAN_THREAD_GLOBAL_PTR(T, V) __declspec(thread) T * V = nullptr
#define LEAN_THREAD_VALUE(T, V, VAL) static __declspec(thread) T V = VAL
#else
#define LEAN_THREAD_PTR(T, V) static __thread T * V = nullptr
#define LEAN_THREAD_EXTERN_PTR(T, V) extern __thread T * V
#define LEAN_THREAD_GLOBAL_PTR(T, V) __thread T * V = nullptr
#define LEAN_THREAD_VALUE(T, V, VAL) static __thread T V = VAL
#endif"""
    if old not in text:
        # TLS may already be patched on a re-run
        if f"defined({MARK})" in text:
            return text
        raise SystemExit("thread.h: TLS block not found")
    return text.replace(old, new, 1)


def patch_thread_cpp(text: str) -> str:
    old = """#ifdef LEAN_WINDOWS
#include <windows.h>
#else
#include <pthread.h>
#endif"""
    new = f"""#ifdef LEAN_WINDOWS
#include <windows.h>
#elif !defined({MARK})
#include <pthread.h>
#endif"""
    if f"!defined({MARK})" in text and "pthread.h" in text:
        return text
    if old not in text:
        raise SystemExit("thread.cpp: pthread include block not found")
    return text.replace(old, new, 1)


def patch_memory_cpp(text: str) -> str:
    if f"defined({MARK})" in text and "get_peak_rss" in text:
        # still ensure throw guard
        pass
    else:
        old = """#else
/* ----------------------------------------------------
   Linux/OSX version for get_peak_rss and get_current_rss
   --------------------------------------------------- */
#include <unistd.h>
#include <sys/resource.h>"""
        new = f"""#elif defined({MARK})
namespace lean {{
size_t get_peak_rss() {{ return 0; }}
size_t get_current_rss() {{ return 0; }}
}}
#else
/* ----------------------------------------------------
   Linux/OSX version for get_peak_rss and get_current_rss
   --------------------------------------------------- */
#include <unistd.h>
#include <sys/resource.h>"""
        if old not in text:
            raise SystemExit("memory.cpp: RSS branch not found")
        text = text.replace(old, new, 1)

    old_throw = """void throw_memory_exception(char const * component_name) {
    throw memory_exception(component_name);
}"""
    new_throw = f"""void throw_memory_exception(char const * component_name) {{
#ifndef {MARK}
    throw memory_exception(component_name);
#else
    (void)component_name;
#endif
}}"""
    if f"#ifndef {MARK}" in text and "throw_memory_exception" in text:
        return text
    if old_throw not in text:
        raise SystemExit("memory.cpp: throw_memory_exception not found")
    return text.replace(old_throw, new_throw, 1)


def patch_stackinfo_cpp(text: str) -> str:
    if "0x1F0400" in text:
        return text
    old1 = """void throw_get_stack_size_failed() {
    throw exception("failed to retrieve thread stack size");
}"""
    new1 = f"""void throw_get_stack_size_failed() {{
#ifndef {MARK}
    throw exception("failed to retrieve thread stack size");
#endif
}}"""
    if old1 not in text:
        raise SystemExit("stackinfo.cpp: throw_get_stack_size_failed not found")
    text = text.replace(old1, new1, 1)

    old2 = """#elif defined(LEAN_EMSCRIPTEN)
size_t get_stack_size(bool main) {
    if (main) {
        return emscripten_stack_get_end() - emscripten_stack_get_base();
    } else {
        return lthread::get_thread_stack_size();
    }
}
#else
size_t get_stack_size(bool main) {"""
    new2 = f"""#elif defined(LEAN_EMSCRIPTEN)
size_t get_stack_size(bool main) {{
    if (main) {{
        return emscripten_stack_get_end() - emscripten_stack_get_base();
    }} else {{
        return lthread::get_thread_stack_size();
    }}
}}
#elif defined({MARK})
size_t get_stack_size(bool /* main */) {{
    return 0x1F0400;
}}
#else
size_t get_stack_size(bool main) {{"""
    if old2 not in text:
        raise SystemExit("stackinfo.cpp: get_stack_size branch not found")
    text = text.replace(old2, new2, 1)

    old3 = """void throw_stack_space_exception(char const * component_name) {
    throw stack_space_exception(component_name);
}"""
    new3 = f"""void throw_stack_space_exception(char const * component_name) {{
#ifndef {MARK}
    throw stack_space_exception(component_name);
#else
    (void)component_name;
#endif
}}"""
    if old3 not in text:
        raise SystemExit("stackinfo.cpp: throw_stack_space_exception not found")
    return text.replace(old3, new3, 1)


def patch_stack_overflow_cpp(text: str) -> str:
    if f"defined({MARK})" in text and "stack_guard::stack_guard" in text:
        return text
    old_inc = """#ifdef LEAN_WINDOWS
#include <windows.h>
#else
#include <csignal>
#include <pthread.h>
#include <unistd.h>
#endif"""
    new_inc = f"""#ifdef LEAN_WINDOWS
#include <windows.h>
#elif !defined({MARK})
#include <csignal>
#include <pthread.h>
#include <unistd.h>
#endif"""
    if old_inc not in text:
        raise SystemExit("stack_overflow.cpp: includes not found")
    text = text.replace(old_inc, new_inc, 1)

    old_body = """stack_guard::~stack_guard() {}
#else
// Install a segfault signal handler and abort with custom message if address is within stack guard."""
    new_body = f"""stack_guard::~stack_guard() {{}}
#elif defined({MARK})
stack_guard::stack_guard() {{}}
stack_guard::~stack_guard() {{}}
#else
// Install a segfault signal handler and abort with custom message if address is within stack guard."""
    if old_body not in text:
        raise SystemExit("stack_overflow.cpp: stack_guard branch not found")
    text = text.replace(old_body, new_body, 1)

    old_init = """void initialize_stack_overflow() {
    g_stack_guard = new stack_guard();
#ifdef LEAN_WINDOWS
    AddVectoredExceptionHandler(0, stack_overflow_handler);
#else
    for (auto signum : {SIGSEGV, SIGBUS}) {
        struct sigaction action;
        memset(&action, 0, sizeof(struct sigaction));
        sigaction(signum, nullptr, &action);
        // Configure our signal handler if one is not already set.
        if (action.sa_handler == SIG_DFL) {
            action.sa_flags = SA_SIGINFO | SA_ONSTACK;
            action.sa_sigaction = segv_handler;
            sigaction(signum, &action, nullptr);
        }
    }
#endif
}"""
    new_init = f"""void initialize_stack_overflow() {{
    g_stack_guard = new stack_guard();
#ifdef LEAN_WINDOWS
    AddVectoredExceptionHandler(0, stack_overflow_handler);
#elif defined({MARK})
    // no stack overflow handler on SP1
#else
    for (auto signum : {{SIGSEGV, SIGBUS}}) {{
        struct sigaction action;
        memset(&action, 0, sizeof(struct sigaction));
        sigaction(signum, nullptr, &action);
        // Configure our signal handler if one is not already set.
        if (action.sa_handler == SIG_DFL) {{
            action.sa_flags = SA_SIGINFO | SA_ONSTACK;
            action.sa_sigaction = segv_handler;
            sigaction(signum, &action, nullptr);
        }}
    }}
#endif
}}"""
    if old_init not in text:
        raise SystemExit("stack_overflow.cpp: initialize_stack_overflow not found")
    return text.replace(old_init, new_init, 1)


def patch_debug_h(text: str) -> str:
    if f"ifndef {MARK}" in text and "lean_unreachable" in text:
        return text
    old = """#define lean_unreachable() { DEBUG_CODE({lean::notify_assertion_violation(__FILE__, __LINE__, "UNREACHABLE CODE WAS REACHED."); lean::invoke_debugger();}) throw lean::unreachable_reached(); }"""
    new = f"""#ifndef {MARK}
#define lean_unreachable() {{ DEBUG_CODE({{lean::notify_assertion_violation(__FILE__, __LINE__, "UNREACHABLE CODE WAS REACHED."); lean::invoke_debugger();}}) throw lean::unreachable_reached(); }}
#else
#define lean_unreachable() {{ __builtin_unreachable(); }}
#endif"""
    if old not in text:
        raise SystemExit("debug.h: lean_unreachable not found")
    return text.replace(old, new, 1)


def patch_debug_cpp(text: str) -> str:
    stub_body = f"""#include <lean/lean.h>
namespace lean {{
void initialize_debug() {{}}
void finalize_debug() {{}}
void notify_assertion_violation(char const *, int, char const *) {{}}
void enable_debug(char const *) {{}}
void disable_debug(char const *) {{}}
bool is_debug_enabled(char const *) {{ return false; }}
void invoke_debugger() {{}}
bool has_violations() {{ return false; }}
void enable_debug_dialog(bool) {{}}
}}
extern "C" LEAN_EXPORT void lean_notify_assert(const char * fileName, int line, const char * condition) {{
    (void)fileName; (void)line; (void)condition;
}}
"""
    stub = f"#ifdef {MARK}\n{stub_body}#else\n"
    if text.lstrip().startswith(f"#ifdef {MARK}"):
        end = text.find("#else\n")
        if end < 0:
            raise SystemExit("debug.cpp: expected #else after LEAN_SP1 stub")
        sp1_branch = text[:end]
        if "lean_notify_assert" in sp1_branch:
            return text
        # Older stub without lean_notify_assert — replace the LEAN_SP1 branch.
        rest = text[end + len("#else\n") :]
        if rest.rstrip().endswith("#endif"):
            return stub + rest
        return stub + rest + "\n#endif\n"
    return stub + text + "\n#endif\n"


def patch_object_cpp(text: str) -> str:
    # Find first panic_eprintln definition and wrap both overloads if present
    marker = f"#ifdef {MARK}\nstatic void panic_eprintln"
    if marker in text:
        return text
    # Locate the static panic_eprintln that takes size
    idx = text.find("static void panic_eprintln(char const * line, size_t size, bool force_stderr)")
    if idx < 0:
        # maybe different formatting
        idx = text.find("static void panic_eprintln(")
        if idx < 0:
            print("warning: object.cpp panic_eprintln not found; skip", file=sys.stderr)
            return text
    # Insert stub before the first definition, and guard the real implementations
    # Simpler approach: prepend stubs and rename is hard. Wrap with ifdef around a known region.
    # Find end of second overload - look for pattern used in Anoma port notes
    start = idx
    # Find previous newline to insert ifdef
    insert_at = text.rfind("\n", 0, start) + 1
    # Find the second overload end: after "panic_eprintln(line, strlen(line), force_stderr);"
    end_marker = "panic_eprintln(line, strlen(line), force_stderr);\n}"
    end = text.find(end_marker, start)
    if end < 0:
        print("warning: object.cpp second panic_eprintln not found; skip", file=sys.stderr)
        return text
    end = end + len(end_marker)
    real = text[insert_at:end]
    stub = f"""#ifdef {MARK}
static void panic_eprintln(char const * /* line */, size_t /* size */, bool /* force_stderr */) {{}}
static void panic_eprintln(char const * /* line */, bool /* force_stderr */) {{}}
#else
{real}
#endif
"""
    return text[:insert_at] + stub + text[end:]


def patch_interrupt_cpp(text: str) -> str:
    # Repair a prior bad patch that produced `#endif   }`
    text = text.replace("#endif   }", "#endif\n        }")
    old1 = """void throw_heartbeat_exception() {
    throw heartbeat_exception();
}"""
    new1 = f"""void throw_heartbeat_exception() {{
#ifndef {MARK}
    throw heartbeat_exception();
#endif
}}"""
    if old1 in text:
        text = text.replace(old1, new1, 1)

    # Replace whole check_interrupted for a clean SP1 form
    import re

    m = re.search(
        r"void check_interrupted\(\) \{.*?\n\}",
        text,
        re.DOTALL,
    )
    if m and f"defined({MARK})" not in m.group(0):
        repl = f"""void check_interrupted() {{
    if (g_cancel_tk) {{
        if (cancel_tk_is_set(g_cancel_tk)
#if !defined({MARK})
            && !std::uncaught_exceptions()
#endif
        ) {{
#ifndef {MARK}
            throw interrupted();
#endif
        }}
    }}
}}"""
        text = text[: m.start()] + repl + text[m.end() :]
    return text


def patch_mutex_cpp(text: str) -> str:
    old = """extern "C" LEAN_EXPORT obj_res lean_io_condvar_wait(b_obj_arg condvar, b_obj_arg mtx) {
    unique_lock<mutex> lock(*basemutex_get(mtx), std::adopt_lock_t());
    condvar_get(condvar)->wait(lock);
    lock.release();
    return box(0);
}"""
    new = f"""extern "C" LEAN_EXPORT obj_res lean_io_condvar_wait(b_obj_arg condvar, b_obj_arg mtx) {{
#ifndef {MARK}
    unique_lock<mutex> lock(*basemutex_get(mtx), std::adopt_lock_t());
    condvar_get(condvar)->wait(lock);
    lock.release();
#else
    (void)condvar;
    (void)mtx;
#endif
    return box(0);
}}"""
    if f"#ifndef {MARK}" in text and "lean_io_condvar_wait" in text:
        return text
    if old not in text:
        print("warning: mutex.cpp lean_io_condvar_wait not found; skip", file=sys.stderr)
        return text
    return text.replace(old, new, 1)


def patch_compact_cpp(text: str) -> str:
    if f"!defined({MARK})" in text and "sys/mman.h" in text:
        return text
    # Broad include rewrite for the non-Windows block at top — read file structure
    # Replace unconditional unix includes
    old = """#elif !defined(LEAN_WINDOWS)
#include <sys/mman.h>
#include <dlfcn.h>
#endif"""
    # 4.32.1 may have different layout - try several patterns
    candidates = [
        (
            """#include <sys/mman.h>
#include <dlfcn.h>""",
            f"""#if !defined({MARK})
#include <sys/mman.h>
#include <dlfcn.h>
#endif""",
        ),
        (
            """#include <sys/mman.h>""",
            f"""#if !defined({MARK})
#include <sys/mman.h>
#endif""",
        ),
    ]
    changed = False
    for o, n in candidates:
        if o in text and f"!defined({MARK})" not in text.split(o)[0][-40:]:
            # only first mman include
            text = text.replace(o, n, 1)
            changed = True
            break
    if "#include <link.h>" in text and f"!defined({MARK})" not in text:
        text = text.replace(
            "#include <link.h>",
            f"""#if !defined({MARK})
#include <link.h>
#endif""",
            1,
        )
        changed = True
    # get_loaded_libs dl_iterate_phdr
    if "dl_iterate_phdr" in text and f"defined({MARK})" not in text:
        # insert empty branch — look for typical else with dl_iterate
        needle = "dl_iterate_phdr"
        pos = text.find(needle)
        # Find start of the Linux branch - often `#else` before it
        # Safer: wrap call site
        # Find function get_loaded_libs
        fn = text.find("get_loaded_libs")
        if fn >= 0 and pos > fn:
            # Prepend SP1 early return inside function body
            brace = text.find("{", fn)
            if brace > 0:
                insert = f"""
#ifdef {MARK}
    return {{}};
#else
"""
                # need matching endif before function end — too fragile
                pass
        # Alternative: comment that build uses -DLEAN_SP1 and we stub via wrapping includes;
        # if dl_iterate still compiles, add stub function replacement
        text = text.replace(
            "dl_iterate_phdr",
            f"""
#if defined({MARK})
    /* no dl_iterate_phdr on SP1 */
#if 0
dl_iterate_phdr
#endif
#else
dl_iterate_phdr
""",
            1,
        )
        # This is messy - better read the actual get_loaded_libs and patch properly
        changed = True
    if not changed and f"!defined({MARK})" not in text:
        raise SystemExit("compact.cpp: could not patch includes")
    return text


def patch_compact_cpp_v2(path: Path) -> bool:
    """Cleaner compact.cpp patch by reading structure."""
    text = path.read_text()
    if f"LEAN_SP1_COMPACT_PATCHED" in text:
        return False
    # Guard mman/dlfcn/link
    import re

    text2 = text
    text2 = re.sub(
        r"(#include <sys/mman\.h>)",
        rf"#if !defined({MARK})\n\1\n#endif",
        text2,
        count=1,
    )
    text2 = re.sub(
        r"(#include <dlfcn\.h>)",
        rf"#if !defined({MARK})\n\1\n#endif",
        text2,
        count=1,
    )
    text2 = re.sub(
        r"(#include <link\.h>)",
        rf"#if !defined({MARK})\n\1\n#endif",
        text2,
        count=1,
    )

    # Stub get_loaded_libs body on SP1: find function and wrap
    m = re.search(
        r"(static\s+.+?get_loaded_libs\s*\([^)]*\)\s*\{)",
        text2,
        re.DOTALL,
    )
    if not m:
        m = re.search(r"((?:std::)?vector.+?get_loaded_libs\s*\([^)]*\)\s*\{)", text2)
    if m:
        insert_at = m.end()
        stub = f"""
#ifdef {MARK}
    return {{}};
#else
"""
        # Find matching close of function — naive brace count from insert_at
        i = insert_at
        depth = 1
        while i < len(text2) and depth:
            if text2[i] == "{":
                depth += 1
            elif text2[i] == "}":
                depth -= 1
            i += 1
        # i is past closing brace
        body_end = i - 1
        text2 = text2[:insert_at] + stub + text2[insert_at:body_end] + f"\n#endif\n" + text2[body_end:]
    text2 = "/* LEAN_SP1_COMPACT_PATCHED */\n" + text2
    if text2 != text:
        path.write_text(text2)
        print(f"patched {path}")
        return True
    return False


def patch_util_io_h(text: str) -> str:
    if f"#ifndef {MARK}" in text and "throw exception" in text:
        return text
    # Guard throw exception in IO result helpers
    return text.replace(
        "throw exception(error.to_std_string());",
        f"""#ifndef {MARK}
        throw exception(error.to_std_string());
#endif""",
    )


def patch_exception_cpp(text: str) -> str:
    # Any unconditional throws that fire at compile time with -fno-exceptions?
    # Usually only runtime. Skip unless needed.
    return text


def patch_init_module_cpp(text: str) -> str:
    if f"!defined({MARK})" in text and "initialize_libuv" in text:
        return text
    old = """extern "C" LEAN_EXPORT void lean_initialize_runtime_module() {
    initialize_alloc();
    initialize_debug();
    initialize_object();
    initialize_io();
    initialize_thread();
    initialize_mutex();
    initialize_process();
    initialize_stack_overflow();
    initialize_libuv();
}
void initialize_runtime_module() {
    lean_initialize_runtime_module();
}
void finalize_runtime_module() {
    finalize_stack_overflow();
    finalize_process();
    finalize_mutex();
    finalize_thread();
    finalize_io();
    finalize_object();
    finalize_debug();"""
    new = f"""extern "C" LEAN_EXPORT void lean_initialize_runtime_module() {{
    initialize_alloc();
    initialize_debug();
    initialize_object();
#if !defined({MARK})
    initialize_io();
#endif
    initialize_thread();
    initialize_mutex();
#if !defined({MARK})
    initialize_process();
#endif
    initialize_stack_overflow();
#if !defined({MARK})
    initialize_libuv();
#endif
}}
void initialize_runtime_module() {{
    lean_initialize_runtime_module();
}}
void finalize_runtime_module() {{
    finalize_stack_overflow();
#if !defined({MARK})
    finalize_process();
#endif
    finalize_mutex();
    finalize_thread();
#if !defined({MARK})
    finalize_io();
#endif
    finalize_object();
    finalize_debug();"""
    if old not in text:
        raise SystemExit("init_module.cpp: initialize block not found")
    text = text.replace(old, new, 1)
    text = text.replace(
        '#include "runtime/io.h"\n',
        f'#if !defined({MARK})\n#include "runtime/io.h"\n#endif\n',
        1,
    )
    text = text.replace(
        '#include "runtime/process.h"\n',
        f'#if !defined({MARK})\n#include "runtime/process.h"\n#endif\n',
        1,
    )
    text = text.replace(
        '#include "runtime/libuv.h"\n',
        f'#if !defined({MARK})\n#include "runtime/libuv.h"\n#endif\n',
        1,
    )
    return text


def patch_libuv_h(text: str) -> str:
    if f"LEAN_SP1_LIBUV_STUB" in text:
        return text
    return f"""/* LEAN_SP1_LIBUV_STUB */
#if defined({MARK})
#pragma once
#include <lean/lean.h>
namespace lean {{
extern "C" inline void initialize_libuv() {{}}
extern "C" inline char ** lean_setup_args(int /*argc*/, char ** argv) {{ return argv; }}
extern "C" inline lean_obj_res lean_libuv_version(lean_obj_arg) {{ return lean_box(0); }}
}}
#else
{text}
#endif
"""


def patch_event_loop_h(text: str) -> str:
    text = text.replace(
        "#ifndef LEAN_EMSCRIPTEN\n#include <uv.h>\n#endif",
        f"#if !defined(LEAN_EMSCRIPTEN) && !defined({MARK})\n#include <uv.h>\n#endif",
    )
    # Remaining emscripten guards that wrap UV types
    if f"!defined({MARK})" not in text:
        text = text.replace(
            "#ifndef LEAN_EMSCRIPTEN\n",
            f"#if !defined(LEAN_EMSCRIPTEN) && !defined({MARK})\n",
        )
    return text


def patch_compact_throws(path: Path) -> None:
    text = path.read_text()
    if "LEAN_SP1_THROW_MUTED" in text:
        return
    import re

    # Whole-line throws
    def repl_line(m: re.Match) -> str:
        indent = m.group(1)
        stmt = m.group(2)
        return f"{indent}#ifndef {MARK}\n{indent}{stmt}\n{indent}#else\n{indent}(void)0;\n{indent}#endif"

    text2 = re.sub(r"^([ \t]*)(throw\s+[^;]+;)\s*$", repl_line, text, flags=re.MULTILINE)
    # Same-line after case label: `case Foo: throw ...;`
    text2 = re.sub(
        r"^([ \t]*case\s+\w+:)([ \t]*)(throw\s+[^;]+;)\s*$",
        rf"\1\n\2#ifndef {MARK}\n\2\3\n\2#else\n\2break;\n\2#endif",
        text2,
        flags=re.MULTILINE,
    )
    path.write_text("/* LEAN_SP1_THROW_MUTED */\n" + text2)
    print(f"patched throws in {path}")


def patch_object_once_cold(text: str) -> str:
    """Replace lean_obj_once_cold with a lock-free single-threaded version for SP1."""
    marker = "LEAN_SP1_ONCE_COLD"
    new_body = f"""extern "C" LEAN_EXPORT lean_object* lean_obj_once_cold(lean_object** loc, lean_once_cell_t* tok, lean_object* (*init)(void)) {{
#if defined({MARK})
    /* Do not key off *loc — BSS may be uninitialized on SP1. */
    int *state = reinterpret_cast<int *>(&tok->state);
    if (*state != 1) {{
        *loc = init();
        lean_mark_persistent(*loc);
        *state = 1;
    }}
    return *loc;
#else
    lock_simple_atomic(tok->lock);
    if (tok->state.load() != 1) {{
        *loc = init();
        lean_mark_persistent(*loc);
        tok->state.store(1);
    }}
    unlock_simple_atomic(tok->lock);
    return *loc;
#endif
}}"""
    import re
    # Replace any existing lean_obj_once_cold definition (including prior SP1 patch).
    pat = re.compile(
        r"extern \"C\" LEAN_EXPORT lean_object\* lean_obj_once_cold\(lean_object\*\* loc, lean_once_cell_t\* tok, lean_object\* \(\*init\)\(void\)\) \{.*?\n\}",
        re.DOTALL,
    )
    if not pat.search(text):
        print("warning: lean_obj_once_cold block not found", file=sys.stderr)
        return text
    text = pat.sub(new_body, text, count=1)
    if marker not in text:
        text = f"/* {marker} */\n" + text
    return text

    """Single-threaded SP1: no-op locks (avoid libatomic / A-extension)."""
    marker = "LEAN_SP1_ATOMIC_NOOP"
    if marker in text:
        return text
    # Upgrade older spin patch if present.
    if "LEAN_SP1_ATOMIC_SPIN" in text:
        text = text.replace("/* LEAN_SP1_ATOMIC_SPIN */\n", "")
    old = """void lock_simple_atomic(std::atomic<int>& lock) {
    while (true) {
#if !defined(LEAN_SP1)
        lock.wait(1);
#endif
        int should = 0;
        if (lock.compare_exchange_strong(should, 1)) {
            break;
        }
    }
}

void unlock_simple_atomic(std::atomic<int>& lock) {
    lock.store(0);
#if !defined(LEAN_SP1)
    lock.notify_one();
#endif
}"""
    # Also match pristine upstream (no LEAN_SP1 guards yet).
    old_upstream = """void lock_simple_atomic(std::atomic<int>& lock) {
    while (true) {
        lock.wait(1);
        int should = 0;
        if (lock.compare_exchange_strong(should, 1)) {
            break;
        }
    }
}

void unlock_simple_atomic(std::atomic<int>& lock) {
    lock.store(0);
    lock.notify_one();
}"""
    new = f"""void lock_simple_atomic(std::atomic<int>& lock) {{
#if defined({MARK})
    (void)lock;
#else
    while (true) {{
        lock.wait(1);
        int should = 0;
        if (lock.compare_exchange_strong(should, 1)) {{
            break;
        }}
    }}
#endif
}}

void unlock_simple_atomic(std::atomic<int>& lock) {{
#if defined({MARK})
    (void)lock;
#else
    lock.store(0);
    lock.notify_one();
#endif
}}"""
    if old in text:
        text = text.replace(old, new, 1)
    elif old_upstream in text:
        text = text.replace(old_upstream, new, 1)
    else:
        print("warning: lock_simple_atomic block not found", file=sys.stderr)
        return text
    return f"/* {marker} */\n" + text


def patch_object_bit_cast(text: str) -> str:
    if "LEAN_SP1_BIT_CAST" in text:
        return text
    import re

    def float_from_bits(m: re.Match) -> str:
        ty = m.group(1)
        var = m.group(2)
        return f"""#if defined({MARK})
    {ty} ret;
    static_assert(sizeof(ret) == sizeof({var}), "bit cast size");
    __builtin_memcpy(&ret, &{var}, sizeof(ret));
#else
    {ty} ret = std::bit_cast<{ty}>({var});
#endif"""

    text = re.sub(
        r"(\w+)\s+ret\s*=\s*std::bit_cast<(\w+)>\((\w+)\);",
        lambda m: f"""#if defined({MARK})
    {m.group(1)} ret;
    static_assert(sizeof(ret) == sizeof({m.group(3)}), "bit cast size");
    __builtin_memcpy(&ret, &{m.group(3)}, sizeof(ret));
#else
    {m.group(1)} ret = std::bit_cast<{m.group(2)}>({m.group(3)});
#endif""",
        text,
    )
    text = re.sub(
        r"return std::bit_cast<(\w+)>\((\w+)\);",
        lambda m: f"""#if defined({MARK})
    {m.group(1)} out;
    static_assert(sizeof(out) == sizeof({m.group(2)}), "bit cast size");
    __builtin_memcpy(&out, &{m.group(2)}, sizeof(out));
    return out;
#else
    return std::bit_cast<{m.group(1)}>({m.group(2)});
#endif""",
        text,
    )
    # lean_sorry: muted lean_always_assert / unreachable leaves no return
    text = re.sub(
        r"(extern \"C\" LEAN_EXPORT object \* lean_sorry\([^)]*\) \{\n)(.*?)(\n\})",
        rf"\1#ifdef {MARK}\n    return lean_box(0);\n#else\n\2\n#endif\3",
        text,
        count=1,
        flags=re.DOTALL,
    )
    return "/* LEAN_SP1_BIT_CAST */\n" + text


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("lean4_src", type=Path, help="Path to lean4 checkout (contains src/runtime)")
    args = ap.parse_args()
    root = args.lean4_src
    rt = root / "src" / "runtime"
    util = root / "src" / "util"
    if not rt.is_dir():
        print(f"missing {rt}", file=sys.stderr)
        return 1

    once(rt / "thread.h", "", patch_thread_h)
    once(rt / "thread.cpp", "", patch_thread_cpp)
    once(rt / "memory.cpp", "", patch_memory_cpp)
    once(rt / "stackinfo.cpp", "", patch_stackinfo_cpp)
    once(rt / "stack_overflow.cpp", "", patch_stack_overflow_cpp)
    once(rt / "debug.h", "", patch_debug_h)
    once(rt / "debug.cpp", "", patch_debug_cpp)
    once(rt / "object.cpp", "", patch_object_cpp)
    once(rt / "object.cpp", "", patch_object_bit_cast)
    once(rt / "object.cpp", "", patch_object_atomics)
    once(rt / "object.cpp", "", patch_object_once_cold)
    once(rt / "interrupt.cpp", "", patch_interrupt_cpp)
    once(rt / "mutex.cpp", "", patch_mutex_cpp)
    once(rt / "init_module.cpp", "", patch_init_module_cpp)
    once(rt / "libuv.h", "", patch_libuv_h)
    once(rt / "uv" / "event_loop.h", "", patch_event_loop_h)
    patch_compact_cpp_v2(rt / "compact.cpp")
    patch_compact_throws(rt / "compact.cpp")

    io_h = util / "io.h"
    if io_h.exists():
        once(io_h, "", patch_util_io_h)
    else:
        print(f"warning: {io_h} missing — expand sparse checkout to include src/util", file=sys.stderr)

    (root / ".lean_sp1_patched").write_text("lean 4.32.1 LEAN_SP1 stubs applied\n")
    print("LEAN_SP1 patches applied")
    return 0


if __name__ == "__main__":
    sys.exit(main())
