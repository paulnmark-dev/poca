FROM nginx:1.27-alpine

# POCA 진단 사이트 (루트 /) 와 WFG 워크숍 사이트 (/wfg/) 를 한 컨테이너에서 서빙
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY site/ /usr/share/nginx/html/
COPY wfg-site/ /usr/share/nginx/html/wfg/

EXPOSE 8080
