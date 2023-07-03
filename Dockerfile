FROM debian:buster-slim
ARG NGINX_VERSION=1.22.0
ARG NGINX_SHA256=b33d569a6f11a01433a57ce17e83935e953ad4dc77cdd4d40f896c88ac26eb53
ARG OPENSSL_VERSION=openssl-3.0.0
ARG OPENSSL_SHA256=59eedfcb46c25214c9bd37ed6078297b4df01d012267fe9e9eee31f61bc70536

RUN apt-get update \
  && apt-get install curl wget build-essential libpcre++-dev libssl-dev git libz-dev ca-certificates unzip --no-install-recommends -y \
  && mkdir -p /usr/local/src \
  && cd /usr/local/src \
  && wget "http://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz" -O "nginx-${NGINX_VERSION}.tar.gz" \
  && echo "$NGINX_SHA256" "nginx-${NGINX_VERSION}.tar.gz" | sha256sum -c - \
  && tar -zxvf "nginx-${NGINX_VERSION}.tar.gz" \
  && wget "https://www.openssl.org/source/old/3.0/${OPENSSL_VERSION}.tar.gz" -O "${OPENSSL_VERSION}.tar.gz" \
  && echo "$OPENSSL_SHA256" "${OPENSSL_VERSION}.tar.gz" | sha256sum -c - \
  && tar -zxvf "${OPENSSL_VERSION}.tar.gz" \
  && cd "nginx-${NGINX_VERSION}" \
  && sed -i 's|--prefix=$ngx_prefix no-shared|--prefix=$ngx_prefix|' auto/lib/openssl/make \
  && ./configure \
  --prefix=/etc/nginx \
  --sbin-path=/usr/sbin/nginx \
  --modules-path=/usr/lib/nginx/modules \
  --conf-path=/etc/nginx/nginx.conf \
  --error-log-path=/var/log/nginx/error.log \
  --http-log-path=/var/log/nginx/access.log \
  --pid-path=/var/run/nginx.pid \
  --lock-path=/var/run/nginx.lock \
  --http-client-body-temp-path=/var/cache/nginx/client_temp \
  --http-proxy-temp-path=/var/cache/nginx/proxy_temp \
  --http-fastcgi-temp-path=/var/cache/nginx/fastcgi_temp \
  --http-uwsgi-temp-path=/var/cache/nginx/uwsgi_temp \
  --http-scgi-temp-path=/var/cache/nginx/scgi_temp \
  --user=www-data \
  --group=www-data \
  --with-compat \
  --with-file-aio \
  --with-threads \
  --with-http_addition_module \
  --with-http_auth_request_module \
  --with-http_dav_module \
  --with-http_flv_module \
  --with-http_gunzip_module \
  --with-http_gzip_static_module \
  --with-http_mp4_module \
  --with-http_random_index_module \
  --with-http_realip_module \
  --with-http_secure_link_module \
  --with-http_slice_module \
  --with-http_ssl_module \
  --with-http_stub_status_module \
  --with-http_sub_module \
  --with-http_v2_module \
  --with-mail \
  --with-mail_ssl_module \
  --with-stream \
  --with-stream_realip_module \
  --with-stream_ssl_module \
  --with-stream_ssl_preread_module \
  --with-openssl="/usr/local/src/${OPENSSL_VERSION}" \
  && make \
  && make install \
  && echo "/usr/local/src/${OPENSSL_VERSION}/.openssl/lib" >> /etc/ld.so.conf.d/ssl.conf && ldconfig \
  && cp "/usr/local/src/${OPENSSL_VERSION}/.openssl/bin/openssl" /usr/bin/openssl \
  && mkdir -p /var/cache/nginx/

# Build Cmake for build GOST-engine
RUN wget -c https://github.com/Kitware/CMake/releases/download/v3.20.1/cmake-3.20.1.tar.gz && \
    tar -zxvf cmake-3.20.1.tar.gz && \
    cd cmake-3.20.1 && \
    ./bootstrap && \
    make && \
    make install

COPY openssl-gost.conf /tmp

#Build GOST-engine for OpenSSL
RUN cd /usr/local/src \
  && git clone https://github.com/gost-engine/engine \
  && cd engine \
  && git submodule update --init \
  && mkdir build \
  && cd build \
  && cmake -DCMAKE_BUILD_TYPE=Release .. \
     -DOPENSSL_ROOT_DIR="/usr/local/src/${OPENSSL_VERSION}/.openssl" \
     -DOPENSSL_INCLUDE_DIR="/usr/local/src/${OPENSSL_VERSION}/.openssl/include" \
     -DOPENSSL_LIBRARIES="/usr/local/src/${OPENSSL_VERSION}/.openssl/lib/" .. \
     -DOPENSSL_ENGINES_DIR="/usr/local/src/${OPENSSL_VERSION}/.openssl/lib/engines-3" \
  && cmake --build . --config Release \
  && cmake --build . --target install --config Release \
  && mkdir /usr/local/src/openssl-3.0.0/.openssl/ssl \
  && cp /etc/ssl/openssl.cnf /usr/local/src/openssl-3.0.0/.openssl/ssl \
  && sed -i 's/openssl_conf = default_conf/openssl_conf = openssl_def/' /usr/local/src/openssl-3.0.0/.openssl/ssl/openssl.cnf \
  && cat /tmp/openssl-gost.conf >> /usr/local/src/openssl-3.0.0/.openssl/ssl/openssl.cnf 

# forward request and error logs to docker log collector
RUN ln -sf /dev/stdout /var/log/nginx/access.log \
	&& ln -sf /dev/stderr /var/log/nginx/error.log

EXPOSE 80

STOPSIGNAL SIGTERM

CMD ["nginx", "-g", "daemon off;"]
