#include <vtzero/vector_tile.hpp>
#include <vtzero/geometry.hpp>

#include <chrono>
#include <cstdint>
#include <fstream>
#include <iostream>
#include <iterator>
#include <string>
#include <vector>

struct geometry_checksum_handler {
    std::uint64_t checksum = 0;

    void points_begin(std::uint32_t n) { checksum += n; }
    void points_point(vtzero::point p) {
        checksum += static_cast<std::uint64_t>(static_cast<std::int64_t>(p.x));
        checksum += static_cast<std::uint64_t>(static_cast<std::int64_t>(p.y));
    }
    void points_end() { checksum += 1; }
    void linestring_begin(std::uint32_t n) { checksum += n; }
    void linestring_point(vtzero::point p) {
        checksum += static_cast<std::uint64_t>(static_cast<std::int64_t>(p.x));
        checksum += static_cast<std::uint64_t>(static_cast<std::int64_t>(p.y));
    }
    void linestring_end() { checksum += 3; }
    void ring_begin(std::uint32_t n) { checksum += n; }
    void ring_point(vtzero::point p) {
        checksum += static_cast<std::uint64_t>(static_cast<std::int64_t>(p.x));
        checksum += static_cast<std::uint64_t>(static_cast<std::int64_t>(p.y));
    }
    void ring_end(vtzero::ring_type rt) {
        checksum += static_cast<std::uint64_t>(rt == vtzero::ring_type::outer ? 0 : rt == vtzero::ring_type::inner ? 1 : 2);
    }
    std::uint64_t result() const { return checksum; }
};

static std::uint64_t parse_tile_bytes(const std::string& data) {
    std::uint64_t checksum = 0;
    vtzero::vector_tile tile{data};
    checksum += static_cast<std::uint64_t>(tile.count_layers());
    while (auto layer = tile.next_layer()) {
        checksum += static_cast<std::uint64_t>(layer.name().size());
        while (auto feature = layer.next_feature()) {
            checksum += feature.id();
            checksum += static_cast<std::uint64_t>(feature.num_properties());
            checksum += static_cast<std::uint64_t>(feature.geometry_type());
        }
    }
    return checksum;
}

static std::uint64_t parse_tile_bytes_decode(const std::string& data) {
    std::uint64_t checksum = 0;
    vtzero::vector_tile tile{data};
    checksum += static_cast<std::uint64_t>(tile.count_layers());
    while (auto layer = tile.next_layer()) {
        checksum += static_cast<std::uint64_t>(layer.name().size());
        while (auto feature = layer.next_feature()) {
            checksum += feature.id();
            checksum += static_cast<std::uint64_t>(feature.num_properties());
            checksum += static_cast<std::uint64_t>(feature.geometry_type());
            geometry_checksum_handler handler;
            checksum += vtzero::decode_geometry(feature.geometry(), handler);
        }
    }
    return checksum;
}

int main(int argc, char** argv) {
    bool decode = false;
    std::size_t iters = 1;
    std::vector<std::string> paths;

    for (int i = 1; i < argc; ++i) {
        const std::string arg = argv[i];
        if (arg == "--decode") {
            decode = true;
            continue;
        }
        if (arg == "--iters") {
            if (i + 1 >= argc) {
                std::cerr << "missing value for --iters\n";
                return 1;
            }
            iters = static_cast<std::size_t>(std::stoull(argv[++i]));
            continue;
        }
        paths.push_back(arg);
    }

    if (paths.empty()) {
        std::cerr << "usage: bench-parse-mvt-cpp [--decode] [--iters N] <tile...>\n";
        return 1;
    }

    try {
        std::vector<std::string> datas;
        datas.reserve(paths.size());
        for (const auto& p : paths) {
            std::ifstream in(p, std::ios::binary);
            if (!in) throw std::runtime_error("failed to open: " + p);
            datas.emplace_back(std::istreambuf_iterator<char>(in), std::istreambuf_iterator<char>());
        }

        std::uint64_t checksum = 0;
        const auto t0 = std::chrono::steady_clock::now();
        for (std::size_t i = 0; i < iters; ++i) {
            for (const auto& data : datas) {
                checksum += decode ? parse_tile_bytes_decode(data) : parse_tile_bytes(data);
            }
        }
        const auto t1 = std::chrono::steady_clock::now();
        const auto elapsed_ns =
            std::chrono::duration_cast<std::chrono::nanoseconds>(t1 - t0).count();

        std::cout << (decode ? "parse+decode" : "parse-only")
                  << '\t' << std::hex << checksum << std::dec
                  << '\t' << elapsed_ns << '\n';
    } catch (const std::exception& e) {
        std::cerr << e.what() << '\n';
        return 1;
    }
    return 0;
}
