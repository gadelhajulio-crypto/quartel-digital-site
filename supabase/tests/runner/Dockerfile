FROM postgres:17-alpine

# Install the pinned pgTAP release into this disposable test image only.
ARG PGTAP_VERSION=1.3.4
RUN apk add --no-cache --virtual .pgtap-build-deps \
      curl \
      make \
      patch \
      perl \
    && curl --fail --silent --show-error --location \
      "https://github.com/theory/pgtap/archive/refs/tags/v${PGTAP_VERSION}.tar.gz" \
      --output /tmp/pgtap.tar.gz \
    && tar -xzf /tmp/pgtap.tar.gz -C /tmp \
    && make -C "/tmp/pgtap-${PGTAP_VERSION}" install \
    && rm -rf "/tmp/pgtap-${PGTAP_VERSION}" /tmp/pgtap.tar.gz \
    && apk del .pgtap-build-deps
