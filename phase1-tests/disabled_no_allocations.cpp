// Disabled profiling must not construct heap-owning recorder state.
#include "BLI_br1_diagnostics.hh"
#include <atomic>
#include <cstdio>
#include <cstdlib>
#include <new>

static std::atomic<size_t> allocations{0};
void *operator new(size_t size)
{
  allocations.fetch_add(1, std::memory_order_relaxed);
  if (void *p = std::malloc(size ? size : 1)) { return p; }
  throw std::bad_alloc();
}
void *operator new[](size_t size) { return ::operator new(size); }
void operator delete(void *p) noexcept { std::free(p); }
void operator delete[](void *p) noexcept { std::free(p); }
void operator delete(void *p, size_t) noexcept { std::free(p); }
void operator delete[](void *p, size_t) noexcept { std::free(p); }

int main()
{
  const auto before = allocations.load(std::memory_order_relaxed);
  if (br1diag::enabled() || br1diag::python_detail_enabled()) { return 2; }
  br1diag::start_session();
  { br1diag::Scope scope(br1diag::Domain::Native, "disabled.regression"); }
  br1diag::frame_boundary();
  br1diag::phase(0);
  br1diag::counter("disabled.counter", 1);
  br1diag::interval(br1diag::Domain::Native, "disabled.interval", 0, 1);
  br1diag::render_marker_begin("disabled.marker");
  br1diag::render_marker_end();
  br1diag::stop_session();
  const auto count = allocations.load(std::memory_order_relaxed) - before;
  std::printf("Disabled profiler heap allocations: %zu\n", count);
  return count == 0 ? 0 : 1;
}
