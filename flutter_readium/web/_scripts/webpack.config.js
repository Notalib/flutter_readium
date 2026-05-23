const path = require("path");
const TerserPlugin = require("terser-webpack-plugin");

module.exports = (argv) => {
  const isDev = argv.mode === "development";
  return {
    mode: argv.mode || "production",
    entry: path.resolve(__dirname, "ReadiumReader.ts"), // Entry point relative to '_scripts'
    output: {
      // TODO: differentiate dev and prod output filenames when ready
      filename: "readiumReader.js", // Name of the output file
      path: path.resolve(__dirname, "../../lib/helpers"), // Output directory inside '../../lib/helpers'
      // Inline all dynamic imports (e.g. ReadiumCSS variants in @readium/navigator)
      // into the single bundle rather than emitting separate chunk files.
      asyncChunks: false,
    },
    module: {
      rules: [
        {
          test: /\.ts$/, // Process all `.ts` files
          use: {
            loader: "ts-loader",
            options: {
              configFile: path.resolve(__dirname, "tsconfig.json"), // Path to tsconfig.json
            },
          },
          exclude: /node_modules/, // Exclude node_modules
        },
        {
          test: /\.css$/, // Process all `.css` files
          use: ["style-loader", "css-loader"], // Loaders for CSS
        },
      ],
    },
    resolve: {
      extensions: [".ts", ".js", ".css"], // Automatically resolve these extensions
    },
    optimization: {
      minimize: !isDev,
      // Disable automatic code-splitting so the entire bundle lands in a single
      // readiumReader.js file.  Without this, Webpack 5's default splitChunks
      // behaviour shards the pre-split @readium/* packages into 30+ chunk files
      // (locale and ReadiumCSS variants) that must be committed alongside the
      // main bundle and served from the same directory.
      splitChunks: false,
      runtimeChunk: false,
      minimizer: [
        new TerserPlugin({
          terserOptions: {
            compress: {
              pure_funcs: ["console.log"], // Remove console.log only
            },
          },
        }),
      ],
    },
  };
};
