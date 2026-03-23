import os

build_num  = os.environ['BUILD_NUM']
git_sha    = os.environ['GIT_SHA'][:7]
build_date = os.environ['BUILD_DATE'][:16].replace('T', ' ') + ' UTC'

css = (
    '<style>'
    '#build-badge{'
    'position:fixed;bottom:8px;right:10px;z-index:9999;'
    'font-family:monospace;font-size:11px;'
    'color:rgba(255,255,255,.55);background:rgba(0,0,0,.45);'
    'padding:3px 7px;border-radius:4px;'
    'pointer-events:none;letter-spacing:.03em;'
    '}'
    '</style>'
)
html = f'<div id="build-badge">#{build_num} &nbsp;{git_sha} &nbsp;{build_date}</div>'

path = 'build/web/index.html'
text = open(path).read()
text = text.replace('</head>', css + '</head>', 1)
text = text.replace('</body>', html + '</body>', 1)
open(path, 'w').write(text)
