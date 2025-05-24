FROM nginx:alpine

# Copy the website files to nginx html directory
COPY website/ /usr/share/nginx/html/

# Copy nginx configuration if needed (optional)
# COPY nginx.conf /etc/nginx/nginx.conf

# Expose port 80
EXPOSE 80

# Start nginx
CMD ["nginx", "-g", "daemon off;"] 