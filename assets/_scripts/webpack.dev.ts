import * as CopyPlugin from 'copy-webpack-plugin';
import * as HtmlWebpackPlugin from 'html-webpack-plugin';
import * as webpack from 'webpack';
import { getEnvVariables, outputPath, resolveApp } from './webpack.tools';

export default <webpack.Configuration>{
  entry: {
    main: './src/index.ts',
  },
  mode: 'development',
  devtool: 'inline-source-map',
  watch: process.env.WATCH == 'true',
  devServer: {
    static: outputPath,
    port: 4200,
    open: true,
  },
  optimization: {
    minimize: false,
  },
  plugins: [
    new CopyPlugin({
      patterns: [
        {
          from: 'public',
        },
        {
          from: 'node_modules/readium-css/css/src',
        },
      ],
    }),
    new HtmlWebpackPlugin({
      inject: false,
      template: resolveApp('src/index.html'),
      ...getEnvVariables(),
    }),
  ],
};
