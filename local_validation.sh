ls -lh ./ares/data/index.json
ls -lh ./ares/data/export_query_index.json

docker exec -it broadsea-ares sh -lc \
  'ls -lh /usr/share/nginx/html/ares/data'