import * as path from 'path';

export function resolveApp(relativePath: string): string {
  return path.resolve(__dirname, relativePath);
}

export function getPublicPath() {
  const homePage = require(resolveApp('package.json')).homepage;

  if (process.env.NODE_ENV === 'development') {
    return '';
  } else if (process.env.PUBLIC_URL) {
    return process.env.PUBLIC_URL;
  } else if (homePage) {
    return homePage;
  }
  return '/';
}

export function getEnvVariables() {
  return { PUBLIC_URL: getPublicPath(), VERSION: require(resolveApp('package.json')).version };
}

let relativeOutputPath = ['dist'];
if (process.env.IS_FLUTTER) {
  relativeOutputPath = ['..', 'helpers'];
}

export const outputPath = path.resolve(__dirname, ...relativeOutputPath);
