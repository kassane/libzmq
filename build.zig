//! Requires zig version: 0.11 or higher
/// build: zig build -Doptimize=ReleaseFast -DShared (or -DShared=true/false)
const std = @import("std");
const Builder = std.Build;

const pkgBuilder = struct {
    mode: std.builtin.OptimizeMode,
    target: std.zig.CrossTarget,
    build: *std.Build.CompileStep,
    configH: *std.Build.ConfigHeaderStep,
};

pub fn build(b: *Builder) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Option - static library [default]
    const shared = b.option(bool, "Shared", "Build the Shared Library [default: false]") orelse false;
    const perf = b.option(bool, "Perf", "Build perf-tools [default: false]") orelse false;

    // Generating "platform.hpp"
    const config_header = switch (target.getOsTag()) {
        .linux => b.addConfigHeader(.{
            .style = .blank,
            .include_path = "platform.hpp",
        }, .{
            .ZMQ_HAVE_LINUX = {},
            .ZMQ_HAVE_PPOLL = {},
            .ZMQ_USE_EPOLL = {},
            .ZMQ_HAVE_CURVE = {},
            .ZMQ_USE_TWEETNACL = {},
            .ZMQ_HAVE_EVENTFD = {},
            .ZMQ_HAVE_IFADDRS = {},
            .ZMQ_HAVE_NOEXCEPT = {},
            .ZMQ_HAVE_SOCK_CLOEXEC = {},
            .ZMQ_HAVE_SO_BINDTODEVICE = {},
            .ZMQ_HAVE_SO_KEEPALIVED = {},
            .ZMQ_HAVE_SO_PEERCRED = {},
            .ZMQ_HAVE_TCP_KEEPCNT = {},
            .ZMQ_HAVE_TCP_KEEPIDLE = {},
            .ZMQ_HAVE_TCP_KEEPINTVL = {},
            .ZMQ_HAVE_UIO = {},
            .ZMQ_CLOCK_GETTIME = {},
            .ZMQ_HAVE_STRLCPY = {},
            .ZMQ_USE_BUILTIN_SHA1 = {},
            .HAVE_FORK = {},
            .ZMQ_HAVE_MKDTEMP = {},
            .HAVE_POSIX_MEMALIGN = 1,
            .HAVE_ACCEPT4 = {},
            .HAVE_IF_NAMETOINDEX = {},
            .HAVE_STRNLEN = {},
            .ZMQ_IOTHREAD_POLLER_USE_EPOLL = {},
            .ZMQ_IOTHREAD_POLLER_USE_EPOLL_CLOEXEC = {},
            .ZMQ_USE_CV_IMPL_STL11 = {},
            .ZMQ_HAVE_IPC = {},
            .ZMQ_POLL_BASED_ON_POLL = {},
            .ZMQ_CACHELINE_SIZE = 64,
            .ZMQ_USE_RADIX_TREE = {},
        }),
        .windows => b.addConfigHeader(.{
            .style = .blank,
            .include_path = "platform.hpp",
        }, .{
            .ZMQ_HAVE_WINDOWS = {},
            .ZMQ_HAVE_MINGW32 = {},
            .ZMQ_HAVE_CURVE = {},
            .ZMQ_USE_TWEETNACL = {},
            .ZMQ_USE_SELECT = {},
            .ZMQ_USE_CV_IMPL_STL11 = {},
            .ZMQ_CACHELINE_SIZE = std.atomic.cache_line,
            .ZMQ_IOTHREAD_POLLER_USE_SELECT = {},
            .ZMQ_POLL_BASED_ON_SELECT = {},
            .ZMQ_USE_BUILTIN_SHA1 = {},
            .HAVE_STRNLEN = 1,
            .ZMQ_USE_RADIX_TREE = {},
        }),
        .macos => b.addConfigHeader(.{
            .style = .blank,
            .include_path = "platform.hpp",
        }, .{
            .ZMQ_HAVE_OSX = {},
            .ZMQ_USE_KQUEUE = {},
            .ZMQ_POSIX_MEMALIGN = 1,
            .ZMQ_CACHELINE_SIZE = std.atomic.cache_line,
            .ZMQ_HAVE_CURVE = {},
            .ZMQ_USE_TWEETNACL = {},
            .ZMQ_HAVE_UIO = {},
            .ZMQ_HAVE_IFADDRS = {},
            .ZMQ_HAVE_OS_KEEPALIVE = {},
            .ZMQ_HAVE_TCP_KEEPALIVE = {},
            .ZMQ_HAVE_TCP_KEEPCNT = {},
            .ZMQ_HAVE_TCP_KEEPINTVL = {},
            .ZMQ_USE_BUILTIN_SHA1 = {},
            .ZMQ_IOTHREAD_POLLER_USE_KQEUE = {},
            .ZMQ_USE_CV_IMPL_STL11 = {},
            .HAVE_STRNLEN = {},
            .HAVE_FORK = {},
        }),
        else => b.addConfigHeader(.{}, .{}),
    };

    const libzmq = if (!shared) b.addStaticLibrary(.{
        .name = "zmq",
        .target = target,
        .optimize = optimize,
    }) else b.addSharedLibrary(.{
        .name = "zmq",
        .target = target,
        .version = .{
            .major = 4,
            .minor = 3,
            .patch = 5,
        },
        .optimize = optimize,
    });
    if (optimize == .Debug or optimize == .ReleaseSafe)
        libzmq.bundle_compiler_rt = true;

    libzmq.strip = true;
    libzmq.addConfigHeader(config_header);
    libzmq.addIncludePath(.{ .path = "include" });
    libzmq.addIncludePath(.{ .path = "src" });
    libzmq.addIncludePath(.{ .path = "external" });
    libzmq.addIncludePath(.{ .path = config_header.include_path });
    libzmq.addCSourceFiles(switch (target.getOsTag()) {
        .windows => cxxSources ++ [_][]const u8{"src/select.cpp"},
        .macos => cxxSources ++ [_][]const u8{"src/kqeue.cpp"},
        .linux => cxxSources ++ [_][]const u8{"src/epoll.cpp"},
        else => cxxSources,
    }, cxxFlags);
    libzmq.addCSourceFiles(extraCsources, cFlags);

    if (target.isWindows()) {
        libzmq.addCSourceFile(.{ .file = .{ .path = "external/wepoll/wepoll.c" }, .flags = cFlags });
        // no pkg-config
        libzmq.linkSystemLibraryName("ws2_32");
        libzmq.linkSystemLibraryName("rpcrt4");
        libzmq.linkSystemLibraryName("iphlpapi");
        // MinGW
        if (target.getAbi() == .gnu) {
            // Need winpthread header & lib (zig has not included)
            libzmq.linkSystemLibraryName("pthread.dll"); // pthread.dll.a (pthread.a get link error)
        }
    } else if (target.isDarwin()) {
        // TODO
        //libzmq.linkFramework("");
    } else {
        // Linux
        libzmq.linkSystemLibrary("rt");
        libzmq.linkSystemLibrary("dl");
    }
    // TODO: MSVC support libC++ (need: ucrt/msvcrt/vcruntime)
    // https://github.com/ziglang/zig/issues/4785 - drop replacement for MSVC
    libzmq.linkLibCpp(); // LLVM libc++ (builtin)
    libzmq.linkLibC(); // OS libc
    b.installArtifact(libzmq);
    libzmq.installHeadersDirectory("include", "");

    if (perf) {
        buildSample(b, .{
            .target = target,
            .mode = optimize,
            .build = libzmq,
            .configH = config_header,
        }, "bench_rt", "perf/benchmark_radix_tree.cpp");
        buildSample(b, .{
            .target = target,
            .mode = optimize,
            .build = libzmq,
            .configH = config_header,
        }, "inproc_lat", "perf/inproc_lat.cpp");
        buildSample(b, .{
            .target = target,
            .mode = optimize,
            .build = libzmq,
            .configH = config_header,
        }, "inproc_thr", "perf/inproc_thr.cpp");
        buildSample(b, .{
            .target = target,
            .mode = optimize,
            .build = libzmq,
            .configH = config_header,
        }, "local_lat", "perf/local_lat.cpp");
        buildSample(b, .{
            .target = target,
            .mode = optimize,
            .build = libzmq,
            .configH = config_header,
        }, "local_thr", "perf/local_thr.cpp");
        buildSample(b, .{
            .target = target,
            .mode = optimize,
            .build = libzmq,
            .configH = config_header,
        }, "proxy_thr", "perf/proxy_thr.cpp");
        buildSample(b, .{
            .target = target,
            .mode = optimize,
            .build = libzmq,
            .configH = config_header,
        }, "remote_thr", "perf/remote_thr.cpp");
        buildSample(b, .{
            .target = target,
            .mode = optimize,
            .build = libzmq,
            .configH = config_header,
        }, "remote_lat", "perf/remote_lat.cpp");
    }
}

fn buildSample(b: *std.Build.Builder, lib: pkgBuilder, name: []const u8, file: []const u8) void {
    const test_exe = b.addExecutable(.{
        .name = name,
        .optimize = lib.mode,
        .target = lib.target,
    });
    test_exe.linkLibrary(lib.build);
    test_exe.addConfigHeader(lib.configH);
    test_exe.addIncludePath(.{ .path = lib.configH.include_path });
    test_exe.addSystemIncludePath(.{ .path = "src" });
    test_exe.addCSourceFile(.{ .file = .{ .path = file }, .flags = cFlags });
    if (lib.target.isWindows())
        test_exe.linkSystemLibraryName("ws2_32");
    test_exe.linkLibCpp();
    b.installArtifact(test_exe);

    const run_cmd = b.addRunArtifact(test_exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step(b.fmt("{s}", .{name}), b.fmt("Run the {s}", .{name}));
    run_step.dependOn(&run_cmd.step);
}

const cFlags: []const []const u8 = &.{
    "-Wall",
    "-pedantic",
    "-Wno-long-long",
    "-Wno-uninitialized",
};
const cxxFlags = cFlags;
const cxxSources: []const []const u8 = &.{
    "src/address.cpp",
    "src/channel.cpp",
    "src/client.cpp",
    "src/clock.cpp",
    "src/ctx.cpp",
    "src/curve_client.cpp",
    "src/curve_mechanism_base.cpp",
    "src/curve_server.cpp",
    "src/dealer.cpp",
    "src/decoder_allocators.cpp",
    "src/devpoll.cpp",
    "src/dgram.cpp",
    "src/dish.cpp",
    "src/dist.cpp",
    "src/endpoint.cpp",
    "src/err.cpp",
    "src/fq.cpp",
    "src/gather.cpp",
    "src/gssapi_client.cpp",
    "src/gssapi_mechanism_base.cpp",
    "src/gssapi_server.cpp",
    "src/io_object.cpp",
    "src/io_thread.cpp",
    "src/ip.cpp",
    "src/ip_resolver.cpp",
    "src/ipc_address.cpp",
    "src/ipc_connecter.cpp",
    "src/ipc_listener.cpp",
    "src/lb.cpp",
    "src/mailbox.cpp",
    "src/mailbox_safe.cpp",
    "src/mechanism.cpp",
    "src/mechanism_base.cpp",
    "src/metadata.cpp",
    "src/msg.cpp",
    "src/mtrie.cpp",
    "src/norm_engine.cpp",
    "src/null_mechanism.cpp",
    "src/object.cpp",
    "src/options.cpp",
    "src/own.cpp",
    "src/pair.cpp",
    "src/peer.cpp",
    "src/pgm_receiver.cpp",
    "src/pgm_sender.cpp",
    "src/pgm_socket.cpp",
    "src/pipe.cpp",
    "src/plain_client.cpp",
    "src/plain_server.cpp",
    "src/poll.cpp",
    "src/poller_base.cpp",
    "src/polling_util.cpp",
    "src/pollset.cpp",
    "src/precompiled.cpp",
    "src/proxy.cpp",
    "src/pub.cpp",
    "src/pull.cpp",
    "src/push.cpp",
    "src/radio.cpp",
    "src/radix_tree.cpp",
    "src/random.cpp",
    "src/raw_decoder.cpp",
    "src/raw_encoder.cpp",
    "src/raw_engine.cpp",
    "src/reaper.cpp",
    "src/rep.cpp",
    "src/req.cpp",
    "src/router.cpp",
    "src/scatter.cpp",
    "src/server.cpp",
    "src/session_base.cpp",
    "src/signaler.cpp",
    "src/socket_base.cpp",
    "src/socket_poller.cpp",
    "src/socks.cpp",
    "src/socks_connecter.cpp",
    "src/stream.cpp",
    "src/stream_connecter_base.cpp",
    "src/stream_engine_base.cpp",
    "src/stream_listener_base.cpp",
    "src/sub.cpp",
    "src/tcp.cpp",
    "src/tcp_address.cpp",
    "src/tcp_connecter.cpp",
    "src/tcp_listener.cpp",
    "src/thread.cpp",
    "src/timers.cpp",
    "src/tipc_address.cpp",
    "src/tipc_connecter.cpp",
    "src/tipc_listener.cpp",
    "src/trie.cpp",
    "src/udp_address.cpp",
    "src/udp_engine.cpp",
    "src/v1_decoder.cpp",
    "src/v1_encoder.cpp",
    "src/v2_decoder.cpp",
    "src/v2_encoder.cpp",
    "src/v3_1_encoder.cpp",
    "src/xpub.cpp",
    "src/xsub.cpp",
    "src/zap_client.cpp",
    "src/zmq.cpp",
    "src/zmq_utils.cpp",
    "src/zmtp_engine.cpp",
};
const extraCsources: []const []const u8 = &.{
    "src/tweetnacl.c",
    "external/sha1/sha1.c",
};
