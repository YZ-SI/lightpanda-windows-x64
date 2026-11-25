"""Adapt the pinned Zig V8 C bindings to the Windows x64 C++ callback ABI."""

from pathlib import Path
import sys


def apply(source: str) -> str:
    def replace(old: str, new: str) -> None:
        nonlocal source
        if source.count(old) != 1:
            raise RuntimeError(f"Review the Windows V8 adaptation for {old.splitlines()[0]}")
        source = source.replace(old, new, 1)

    replace(
        '#include "unicode/locid.h"',
        '#include "unicode/locid.h"\n#include "unicode/timezone.h"',
    )
    # This block is scoped to the Windows archive built by build-v8.ps1.
    replace(
        'extern "C" {\n\n// Platform',
        '''// V8's C++ ABI for returning MaybeLocal is distinct from a pointer
// return on Windows x64. These thunks keep C++ types on the V8 side.
using WinResolveModule = const v8::Module* (*)(
    const v8::Context*, const v8::String*, const v8::FixedArray*, const v8::Module*);
using WinImportModule = v8::Promise* (*)(
    v8::Context*, v8::Data*, v8::Value*, v8::String*, v8::FixedArray*);

static thread_local WinResolveModule win_resolve_module = nullptr;
static std::atomic<bool> win_timezone_overridden{false};

class ScopedWinResolveModule {
public:
    explicit ScopedWinResolveModule(WinResolveModule next) : previous_(win_resolve_module) {
        win_resolve_module = next;
    }
    ~ScopedWinResolveModule() { win_resolve_module = previous_; }

private:
    WinResolveModule previous_;
};

static v8::MaybeLocal<v8::Module> winResolveModule(
    v8::Local<v8::Context> context,
    v8::Local<v8::String> specifier,
    v8::Local<v8::FixedArray> attributes,
    v8::Local<v8::Module> referrer) {
    const auto* module = win_resolve_module(
        local_to_ptr(context), local_to_ptr(specifier), local_to_ptr(attributes),
        local_to_ptr(referrer));
    return module ? v8::MaybeLocal<v8::Module>(ptr_to_local(module))
                  : v8::MaybeLocal<v8::Module>();
}

// Lightpanda leaves the last isolate embedder slot available to this binding.
static constexpr uint32_t win_import_slot = v8::internal::Internals::kNumIsolateDataSlots - 1;

static v8::MaybeLocal<v8::Promise> winImportModule(
    v8::Local<v8::Context> context,
    v8::Local<v8::Data> options,
    v8::Local<v8::Value> resource,
    v8::Local<v8::String> specifier,
    v8::Local<v8::FixedArray> attributes) {
    auto callback = reinterpret_cast<WinImportModule>(
        v8::Isolate::GetCurrent()->GetData(win_import_slot));
    auto* promise = callback(local_to_ptr(context), local_to_ptr(options),
                             local_to_ptr(resource), local_to_ptr(specifier),
                             local_to_ptr(attributes));
    return promise ? v8::MaybeLocal<v8::Promise>(ptr_to_local(promise))
                   : v8::MaybeLocal<v8::Promise>();
}

extern "C" {

// Platform''',
    )
    replace(
        'v8::HostImportModuleDynamicallyCallback callback) {\n'
        '    isolate->SetHostImportModuleDynamicallyCallback(callback);',
        '''WinImportModule callback) {
    isolate->SetData(win_import_slot, reinterpret_cast<void*>(callback));
    isolate->SetHostImportModuleDynamicallyCallback(callback ? winImportModule : nullptr);''',
    )
    replace(
        'v8::Module::ResolveModuleCallback cb,\n'
        '        v8::Maybe<bool>* out) {\n'
        '    *out = ptr_to_local(&self)->InstantiateModule(ptr_to_local(&ctx), cb);',
        '''WinResolveModule cb,
        v8::Maybe<bool>* out) {
    ScopedWinResolveModule scope(cb);
    *out = ptr_to_local(&self)->InstantiateModule(ptr_to_local(&ctx), winResolveModule);''',
    )
    replace(
        'bool v8__V8__InitializeICU() { return v8::V8::InitializeICU(); }',
        '''bool v8__V8__InitializeICU() { return v8::V8::InitializeICU(); }

void lp_win_v8_set_default_timezone(const char* id) {
    icu::TimeZone::adoptDefault(icu::TimeZone::createTimeZone(icu::UnicodeString::fromUTF8(id)));
    win_timezone_overridden.store(true, std::memory_order_release);
}

int lp_win_v8_timezone_offset(int64_t timestamp, int32_t* seconds) {
    if (!win_timezone_overridden.load(std::memory_order_acquire)) return 0;
    const std::unique_ptr<icu::TimeZone> zone(icu::TimeZone::createDefault());
    UErrorCode status = U_ZERO_ERROR;
    int32_t raw, daylight;
    zone->getOffset(static_cast<UDate>(timestamp) * 1000, false, raw, daylight, status);
    if (U_FAILURE(status)) return 0;
    *seconds = (raw + daylight) / 1000;
    return 1;
}''',
    )
    return source


def main() -> None:
    original, destination = map(Path, sys.argv[1:])
    generated = apply(original.read_text(encoding="utf-8")).encode("utf-8")
    if not destination.exists() or destination.read_bytes() != generated:
        destination.write_bytes(generated)


if __name__ == "__main__":
    main()
