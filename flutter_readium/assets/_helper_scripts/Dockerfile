FROM node:lts AS compile-image

LABEL name="Webpack starter" \
      description="This image is for webpack typescript starter."

WORKDIR /app
COPY package*.json ./

RUN npm ci

COPY . ./ 
RUN npm run build

FROM nginx
COPY nginx.conf /etc/nginx/conf.d/default.conf 
COPY --from=compile-image /app/dist /usr/share/nginx/html
