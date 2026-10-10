#pragma once
// Test-only observation. No production API, loader override or physics mutation.
#include <FGJSBBase.h>
#include <filesystem>
#include <stdexcept>
#include <string>
#include <string_view>
#include <vector>
#ifdef _WIN32
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
// Windows defines ERROR as a macro; JSBSim uses LogLevel::ERROR in headers
// included by this test's callers. Keep this observation helper nonpolluting.
#ifdef ERROR
#undef ERROR
#endif
#else
#include <dlfcn.h>
#endif

namespace piston_fixture {
struct LibrarySymbol : JSBSim::FGJSBBase {
  using FGJSBBase::CreateIndexedPropertyName;
};
inline std::string loaded_library_path() {
  // Resolve actual exported code; inline GetVersion can refer to consumer data.
  const void* address=reinterpret_cast<const void*>(&LibrarySymbol::CreateIndexedPropertyName);
#ifdef _WIN32
  HMODULE module=nullptr;
  if(!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS|GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,reinterpret_cast<LPCWSTR>(address),&module))
    throw std::runtime_error("Cannot identify actual loaded JSBSim DLL");
  std::vector<wchar_t> path(32768);
  const auto size=GetModuleFileNameW(module,path.data(),static_cast<DWORD>(path.size()));
  if(size==0||size>=path.size()) throw std::runtime_error("Cannot resolve actual loaded JSBSim DLL path");
  const auto utf8=std::filesystem::path(std::wstring(path.data(),size)).u8string();
#else
  Dl_info info{};
  if(!dladdr(address,&info)||!info.dli_fname)
    throw std::runtime_error("Cannot identify actual loaded JSBSim shared object");
  const auto utf8=std::filesystem::canonical(info.dli_fname).u8string();
#endif
  return std::string(utf8.begin(),utf8.end());
}
inline std::string json_path(std::string_view value) {
  // Paths are UTF-8. Preserve non-ASCII bytes; escape JSON punctuation/control.
  constexpr char hex[]="0123456789abcdef";
  std::string result="\"";
  for(unsigned char byte:value) {
    if(byte=='\"'||byte=='\\') { result+='\\';result+=static_cast<char>(byte); }
    else if(byte<32) { result+="\\u00";result+=hex[byte>>4];result+=hex[byte&15]; }
    else result+=static_cast<char>(byte);
  }
  result+='\"';return result;
}
} // namespace piston_fixture
