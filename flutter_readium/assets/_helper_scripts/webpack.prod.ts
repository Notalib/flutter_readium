import TerserPlugin from 'terser-webpack-plugin';
import webpack from 'webpack';

export default <webpack.Configuration>{
  mode: 'production',
  // devtool: 'source-map',
  optimization: {
    minimizer: [new TerserPlugin()],
    minimize: true,

    splitChunks: {
      cacheGroups: {
        vendors: {
          priority: -10,
          test: /[\\/]node_modules[\\/]/,
        },
      },

      chunks: 'async',
      minChunks: 1,
      minSize: 30000,
      name: false,
    },
  },
};
