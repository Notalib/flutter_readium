const path = require('path');

module.exports = {
  mode: 'development', // or 'production'
  entry: path.resolve(__dirname, 'ReadiumReader.ts'), // Entry point relative to '_scripts'
  output: {
    filename: 'readiumReader.js', // Name of the output file
    path: path.resolve(__dirname, '../../lib/helpers'), // Output directory inside '../../lib/helpers'
  },
  module: {
    rules: [
      {
        test: /\.ts$/, // Process all `.ts` files
        use: {
          loader: 'ts-loader',
          options: {
            configFile: path.resolve(__dirname, 'tsconfig.json'), // Path to tsconfig.json
          },
        },
        exclude: /node_modules/, // Exclude node_modules
      },
      {
        test: /\.css$/, // Process all `.css` files
        use: ['style-loader', 'css-loader'], // Loaders for CSS
      },
    ],
  },
  resolve: {
    extensions: ['.ts', '.js', '.css'], // Automatically resolve these extensions
  },
};
