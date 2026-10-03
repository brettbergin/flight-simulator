#include <flight/fdm/model.hpp>
#include "model_hashes.hpp"
#include <array>
#include <bit>
#include <fstream>
#include <iomanip>
#include <sstream>
#include <stdexcept>
#include <vector>

namespace flight::fdm {
std::string sha256(std::span<const std::uint8_t> bytes) {
  constexpr std::array<std::uint32_t, 64> k{0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
    0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,
    0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
    0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,
    0xd192e819,0xd6990624,0xf40e3585,0x106aa070,0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
    0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2};
  std::array<std::uint32_t, 8> hash{0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19};
  if (bytes.size() > 4 * 1024 * 1024) throw std::invalid_argument("SHA input exceeds model bound");
  std::vector<std::uint8_t> padded(bytes.begin(), bytes.end()); padded.push_back(0x80);
  while (padded.size() % 64 != 56) padded.push_back(0);
  const auto bits = static_cast<std::uint64_t>(bytes.size()) * 8;
  for (int i = 7; i >= 0; --i) padded.push_back(static_cast<std::uint8_t>(bits >> (i * 8)));
  for (std::size_t offset = 0; offset < padded.size(); offset += 64) {
    std::array<std::uint32_t, 64> w{};
    for (unsigned i = 0; i < 16; ++i) for (unsigned j = 0; j < 4; ++j) w[i] = (w[i] << 8) | padded[offset + 4 * i + j];
    for (unsigned i = 16; i < 64; ++i) {
      const auto s0 = std::rotr(w[i-15],7)^std::rotr(w[i-15],18)^(w[i-15]>>3);
      const auto s1 = std::rotr(w[i-2],17)^std::rotr(w[i-2],19)^(w[i-2]>>10); w[i]=w[i-16]+s0+w[i-7]+s1;
    }
    auto [a,b,c,d,e,f,g,h] = hash;
    for (unsigned i=0;i<64;++i) {
      const auto t1=h+(std::rotr(e,6)^std::rotr(e,11)^std::rotr(e,25))+((e&f)^(~e&g))+k[i]+w[i];
      const auto t2=(std::rotr(a,2)^std::rotr(a,13)^std::rotr(a,22))+((a&b)^(a&c)^(b&c));
      h=g;g=f;f=e;e=d+t1;d=c;c=b;b=a;a=t1+t2;
    }
    hash[0]+=a;hash[1]+=b;hash[2]+=c;hash[3]+=d;hash[4]+=e;hash[5]+=f;hash[6]+=g;hash[7]+=h;
  }
  std::ostringstream out; out << std::hex << std::setfill('0'); for (auto value : hash) out << std::setw(8) << value; return out.str();
}
void verify_original_model(const std::filesystem::path& root) {
  const auto canonical_root = std::filesystem::canonical(root);
  for (const auto& entry : original_model_files) {
    const auto path = root / entry.path;
    const auto canonical = std::filesystem::canonical(path);
    const auto relative = canonical.lexically_relative(canonical_root);
    if (relative.empty() || *relative.begin() == ".." || !std::filesystem::is_regular_file(canonical) ||
        std::filesystem::file_size(canonical) != entry.bytes) throw std::invalid_argument("Untrusted original model path/size");
    std::ifstream stream(canonical, std::ios::binary); std::vector<std::uint8_t> bytes(static_cast<std::size_t>(entry.bytes));
    stream.read(reinterpret_cast<char*>(bytes.data()), static_cast<std::streamsize>(bytes.size()));
    if (!stream || sha256(bytes) != entry.sha256) throw std::invalid_argument("Original model SHA-256 mismatch");
  }
}
} // namespace flight::fdm
