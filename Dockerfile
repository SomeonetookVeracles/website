# Multi-stage build for optimized production image
FROM node:18-alpine AS builder

# Set working directory
WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm ci --only=production

# Copy source code
COPY . .

# Build React app
RUN npm run build

# Production stage
FROM alpine:3.18

# Install Apache2, Certbot and dependencies
RUN apk add --no-cache \
    apache2 \
    apache2-ssl \
    apache2-utils \
    apache2-mod-wsgi \
    certbot \
    certbot-apache \
    openssl \
    bash \
    curl \
    nodejs \
    npm \
    dos2unix \
    gettext

# Create non-root user
RUN addgroup -g 1001 -S appuser && \
    adduser -S appuser -u 1001

# Set working directory
WORKDIR /app

# Copy built React app from builder stage
COPY --from=builder /app/build /var/www/html

# Copy Apache configuration
COPY apache2.conf /etc/apache2/httpd.conf
COPY site.conf /etc/apache2/conf.d/site.conf

# Create entrypoint script directly in the container to avoid line ending issues
RUN echo '#!/bin/sh' > /entrypoint.sh && \
    echo 'set -e' >> /entrypoint.sh && \
    echo '' >> /entrypoint.sh && \
    echo '# Remove conflicting Apache config files that cause issues' >> /entrypoint.sh && \
    echo 'rm -f /etc/apache2/conf.d/languages.conf' >> /entrypoint.sh && \
    echo 'rm -f /etc/apache2/conf.d/ssl.conf' >> /entrypoint.sh && \
    echo 'rm -f /etc/apache2/conf.d/default.conf' >> /entrypoint.sh && \
    echo '' >> /entrypoint.sh && \
    echo '# Fix permissions' >> /entrypoint.sh && \
    echo 'chown -R apache:apache /var/www/html' >> /entrypoint.sh && \
    echo 'mkdir -p /run/apache2 /var/log/apache2' >> /entrypoint.sh && \
    echo 'chown -R apache:apache /run/apache2 /var/log/apache2' >> /entrypoint.sh && \
    echo '' >> /entrypoint.sh && \
    echo '# Replace environment variables in Apache config' >> /entrypoint.sh && \
    echo 'envsubst \$DOMAIN < /etc/apache2/conf.d/site.conf > /tmp/site.conf' >> /entrypoint.sh && \
    echo 'cp /tmp/site.conf /etc/apache2/conf.d/site.conf' >> /entrypoint.sh && \
    echo '' >> /entrypoint.sh && \
    echo '# Create certbot webroot directory' >> /entrypoint.sh && \
    echo 'mkdir -p /var/www/certbot' >> /entrypoint.sh && \
    echo '' >> /entrypoint.sh && \
    echo '# Start Apache in background for certificate generation' >> /entrypoint.sh && \
    echo 'httpd' >> /entrypoint.sh && \
    echo '' >> /entrypoint.sh && \
    echo '# Wait for Apache to start' >> /entrypoint.sh && \
    echo 'sleep 5' >> /entrypoint.sh && \
    echo '' >> /entrypoint.sh && \
    echo '# Check if we should use staging or production Lets Encrypt' >> /entrypoint.sh && \
    echo 'if [ "$STAGING" = "1" ]; then' >> /entrypoint.sh && \
    echo '    STAGING_FLAG="--staging"' >> /entrypoint.sh && \
    echo 'else' >> /entrypoint.sh && \
    echo '    STAGING_FLAG=""' >> /entrypoint.sh && \
    echo 'fi' >> /entrypoint.sh && \
    echo '' >> /entrypoint.sh && \
    echo '# Request certificate if it does not exist' >> /entrypoint.sh && \
    echo 'if [ ! -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then' >> /entrypoint.sh && \
    echo '    echo "Requesting certificate for $DOMAIN..."' >> /entrypoint.sh && \
    echo '    certbot certonly \' >> /entrypoint.sh && \
    echo '        --webroot \' >> /entrypoint.sh && \
    echo '        --webroot-path=/var/www/certbot \' >> /entrypoint.sh && \
    echo '        --non-interactive \' >> /entrypoint.sh && \
    echo '        --agree-tos \' >> /entrypoint.sh && \
    echo '        --email $EMAIL \' >> /entrypoint.sh && \
    echo '        --domains $DOMAIN \' >> /entrypoint.sh && \
    echo '        $STAGING_FLAG' >> /entrypoint.sh && \
    echo '    ' >> /entrypoint.sh && \
    echo '    # Restart Apache to load certificates' >> /entrypoint.sh && \
    echo '    httpd -k stop' >> /entrypoint.sh && \
    echo '    sleep 2' >> /entrypoint.sh && \
    echo 'fi' >> /entrypoint.sh && \
    echo '' >> /entrypoint.sh && \
    echo '# Auto-renewal check every 12 hours' >> /entrypoint.sh && \
    echo 'while true; do' >> /entrypoint.sh && \
    echo '    sleep 12h' >> /entrypoint.sh && \
    echo '    certbot renew --webroot --webroot-path=/var/www/certbot --quiet' >> /entrypoint.sh && \
    echo '    httpd -k graceful' >> /entrypoint.sh && \
    echo 'done &' >> /entrypoint.sh && \
    echo '' >> /entrypoint.sh && \
    echo '# Start Apache in foreground' >> /entrypoint.sh && \
    echo 'exec httpd -D FOREGROUND' >> /entrypoint.sh && \
    chmod +x /entrypoint.sh

# Create directories and set permissions
RUN mkdir -p /etc/letsencrypt /run/apache2 /var/log/apache2 && \
    chown -R appuser:appuser /etc/letsencrypt /var/www/html /run/apache2 /var/log/apache2 && \
    chmod -R 755 /var/www/html

# Enable Apache modules
RUN sed -i 's/#LoadModule rewrite_module/LoadModule rewrite_module/g' /etc/apache2/httpd.conf && \
    sed -i 's/#LoadModule ssl_module/LoadModule ssl_module/g' /etc/apache2/httpd.conf && \
    sed -i 's/#LoadModule socache_shmcb_module/LoadModule socache_shmcb_module/g' /etc/apache2/httpd.conf && \
    sed -i 's/#LoadModule negotiation_module/LoadModule negotiation_module/g' /etc/apache2/httpd.conf

# Expose ports
EXPOSE 80 443

# Don't switch to non-root user here - entrypoint needs root
# USER appuser

# Start services
ENTRYPOINT ["/entrypoint.sh"]