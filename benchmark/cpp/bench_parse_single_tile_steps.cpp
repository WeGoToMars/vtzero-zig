#include <vtzero/geometry.hpp>
#include <vtzero/vector_tile.hpp>

#include <chrono>
#include <cstdint>
#include <fstream>
#include <iterator>
#include <print>
#include <stdexcept>
#include <string>

namespace {

constexpr const char* default_tile_path =
    "vtzero/test/mvt-fixtures/real-world/chicago/13-2100-3045.mvt";

struct geometry_checksum_handler {
    std::uint64_t checksum = 0;

    void mix_count(std::uint32_t n) {
        checksum += n;
    }

    void mix_point(vtzero::point p) {
        checksum += static_cast<std::uint64_t>(static_cast<std::int64_t>(p.x));
        checksum += static_cast<std::uint64_t>(static_cast<std::int64_t>(p.y));
    }

    void points_begin(std::uint32_t n) { mix_count(n); }
    void points_point(vtzero::point p) { mix_point(p); }
    void points_end() { checksum += 1; }
    void linestring_begin(std::uint32_t n) { mix_count(n); }
    void linestring_point(vtzero::point p) { mix_point(p); }
    void linestring_end() { checksum += 3; }
    void ring_begin(std::uint32_t n) { mix_count(n); }
    void ring_point(vtzero::point p) { mix_point(p); }
    void ring_end(vtzero::ring_type rt) {
        checksum += static_cast<std::uint64_t>(
            rt == vtzero::ring_type::outer ? 0 :
            rt == vtzero::ring_type::inner ? 1 : 2
        );
    }

    std::uint64_t result() const { return checksum; }
};

struct timing_totals {
    std::uint64_t total_ns = 0;
    std::uint64_t tile_init_ns = 0;
    std::uint64_t count_layers_ns = 0;
    std::uint64_t next_layer_ns = 0;
    std::uint64_t layer_metadata_ns = 0;
    std::uint64_t next_feature_ns = 0;
    std::uint64_t feature_metadata_ns = 0;
    std::uint64_t property_indexes_ns = 0;
    std::uint64_t geometry_decode_ns = 0;
};

template <typename TStart>
std::uint64_t elapsed_ns(TStart start) {
    const auto now = std::chrono::steady_clock::now();
    return static_cast<std::uint64_t>(
        std::chrono::duration_cast<std::chrono::nanoseconds>(now - start).count()
    );
}

std::uint64_t run_instrumented_parse(const std::string& data, timing_totals& totals) {
    std::uint64_t checksum = 0;
    const auto total_start = std::chrono::steady_clock::now();

    const auto tile_init_start = std::chrono::steady_clock::now();
    vtzero::vector_tile tile{data};
    totals.tile_init_ns += elapsed_ns(tile_init_start);

    const auto count_layers_start = std::chrono::steady_clock::now();
    checksum += static_cast<std::uint64_t>(tile.count_layers());
    totals.count_layers_ns += elapsed_ns(count_layers_start);

    while (true) {
        const auto next_layer_start = std::chrono::steady_clock::now();
        auto layer = tile.next_layer();
        totals.next_layer_ns += elapsed_ns(next_layer_start);

        if (!layer) {
            break;
        }

        const auto layer_metadata_start = std::chrono::steady_clock::now();
        checksum += static_cast<std::uint64_t>(layer.name().size());
        checksum += static_cast<std::uint64_t>(layer.num_features());
        checksum += static_cast<std::uint64_t>(layer.key_table_size());
        checksum += static_cast<std::uint64_t>(layer.value_table_size());
        totals.layer_metadata_ns += elapsed_ns(layer_metadata_start);

        while (true) {
            const auto next_feature_start = std::chrono::steady_clock::now();
            auto feature = layer.next_feature();
            totals.next_feature_ns += elapsed_ns(next_feature_start);

            if (!feature) {
                break;
            }

            const auto feature_metadata_start = std::chrono::steady_clock::now();
            checksum += feature.id();
            checksum += static_cast<std::uint64_t>(feature.num_properties());
            checksum += static_cast<std::uint64_t>(feature.geometry_type());
            totals.feature_metadata_ns += elapsed_ns(feature_metadata_start);

            const auto property_indexes_start = std::chrono::steady_clock::now();
            while (true) {
                const auto idx = feature.next_property_indexes();
                if (!idx) {
                    break;
                }
                checksum += static_cast<std::uint64_t>(idx.key().value());
                checksum += static_cast<std::uint64_t>(idx.value().value());
            }
            totals.property_indexes_ns += elapsed_ns(property_indexes_start);

            const auto decode_start = std::chrono::steady_clock::now();
            geometry_checksum_handler handler;
            checksum += vtzero::decode_geometry(feature.geometry(), handler);
            totals.geometry_decode_ns += elapsed_ns(decode_start);
        }
    }

    totals.total_ns += elapsed_ns(total_start);
    return checksum;
}

void print_step(
    const char* label,
    std::uint64_t step_ns,
    std::uint64_t total_ns,
    std::size_t iters
) {
    const double ns_per_iter = static_cast<double>(step_ns) / static_cast<double>(iters);
    const double pct_total = total_ns == 0
        ? 0.0
        : (static_cast<double>(step_ns) * 100.0) / static_cast<double>(total_ns);

    std::print("{:<20} {:<10} {:<12.2f} {:<12.2f}\n", label, step_ns, ns_per_iter, pct_total);
}

} // namespace

int main(int argc, char** argv) {
    std::string tile_path = default_tile_path;
    bool saw_tile_arg = false;
    std::size_t iters = 10000;

    for (int i = 1; i < argc; ++i) {
        const std::string arg = argv[i];
        if (arg == "--iters") {
            if (i + 1 >= argc) {
                std::println(stderr, "missing value for --iters");
                return 1;
            }
            iters = static_cast<std::size_t>(std::stoull(argv[++i]));
            continue;
        }

        if (saw_tile_arg) {
            std::println(stderr, "only one tile path is supported");
            return 1;
        }
        tile_path = arg;
        saw_tile_arg = true;
    }

    try {
        std::ifstream in(tile_path, std::ios::binary);
        if (!in) {
            throw std::runtime_error("failed to open: " + tile_path);
        }
        const std::string data{
            std::istreambuf_iterator<char>(in),
            std::istreambuf_iterator<char>()
        };

        timing_totals totals{};
        std::uint64_t checksum = 0;
        for (std::size_t i = 0; i < iters; ++i) {
            checksum += run_instrumented_parse(data, totals);
        }

        std::print(
            "single-tile-steps\tpath={}\titers={}\tchecksum={:x}\n",
            tile_path,
            iters,
            checksum
        );

        std::print("{:<20} {:<10} {:<12} {:<12}\n", "step", "total_ns", "ns_per_iter", "pct_of_total");
        std::print("---------------------------------------------------------\n");

        print_step("tile_init", totals.tile_init_ns, totals.total_ns, iters);
        print_step("count_layers", totals.count_layers_ns, totals.total_ns, iters);
        print_step("next_layer", totals.next_layer_ns, totals.total_ns, iters);
        print_step("layer_metadata", totals.layer_metadata_ns, totals.total_ns, iters);
        print_step("next_feature", totals.next_feature_ns, totals.total_ns, iters);
        print_step("feature_metadata", totals.feature_metadata_ns, totals.total_ns, iters);
        print_step("property_indexes", totals.property_indexes_ns, totals.total_ns, iters);
        print_step("geometry_decode", totals.geometry_decode_ns, totals.total_ns, iters);
        print_step("total_parse", totals.total_ns, totals.total_ns, iters);
    } catch (const std::exception& e) {
        std::println(stderr, "{}", e.what());
        return 1;
    }

    return 0;
}
