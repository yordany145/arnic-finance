# Imagen mínima (plantilla oficial de dart.dev): compila a un ejecutable AOT
# y lo corre sin el SDK completo dentro de la imagen final.
FROM dart:stable AS build
WORKDIR /app
COPY pubspec.* ./
RUN dart pub get
COPY . .
RUN dart pub get --offline
RUN dart run build_runner build
# `dart compile exe` todavía no soporta los "build hooks" que usa el paquete
# sqlite3 para preparar su librería nativa; `dart build cli` sí.
RUN dart build cli -o /app/out

FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /app/out/bundle/ /app/
EXPOSE 8080
ENTRYPOINT ["/app/bin/server"]
