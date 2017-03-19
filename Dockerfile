FROM scratch
LABEL maintainer "Marc Carre <carre.marc@gmail.com>"
ARG version_tag
ENV VERSION_TAG=${version_tag}
ADD ./dist ./dist
ENTRYPOINT ["/bin/sh"]
