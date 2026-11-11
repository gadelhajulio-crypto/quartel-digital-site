import type { MetadataRoute } from "next";

export default function manifest(): MetadataRoute.Manifest {
  return {
    name: "Quartel Digital",
    short_name: "Quartel Digital",
    start_url: "/",
    display: "browser",
    background_color: "#151716",
    theme_color: "#102820",
    icons: [192, 512].map((size) => ({
      src: `/assets/brand/quartel-digital-v1/QD_favicon_mira_${size}.png`,
      sizes: `${size}x${size}`,
      type: "image/png",
      purpose: "any",
    })),
  };
}
