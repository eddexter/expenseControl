FROM public.ecr.aws/awsguru/aws-lambda-adapter:0.9.0 AS adapter

FROM node:20-slim
COPY --from=adapter /lambda-adapter /opt/extensions/lambda-adapter

WORKDIR /var/task
COPY package*.json ./
RUN npm ci --omit=dev

COPY src ./src

ENV PORT=8080
EXPOSE 8080

CMD ["node", "src/http.js"]
