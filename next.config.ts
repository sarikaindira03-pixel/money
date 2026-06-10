import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  reactStrictMode: false,
  allowedDevOrigins: ["*.ngrok-free.dev", "*.ngrok.io"],
  images: {
    remotePatterns: [{ hostname: "example.com" }],
  },
  async rewrites() {
    return [
      {
        source: "/api/proxy/:path*",
        destination: "http://localhost:8081/rest/v1/:path*",
      },
    ];
  },
};

export default nextConfig;
