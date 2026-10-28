"""The demo workspace behind the website's and the stores' screenshots.

python3 design/store/demo-workspace.py <data dir> writes <data dir>/Workspace/pages/*.json — page files as the app
keeps them — which a run with HIKKI_DATA_DIR=<data dir> HIKKI_WORKSPACE=Personal imports at launch. Ids are fixed per
title (`en-` + a hash), so HIKKI_DEBUG_NAV / HIKKI_OPEN_TABS can open one: Launch week en-b2e3a009d7fc, Product launch
en-f725dda9d6d5, Design notes en-8d64ef1034cc, Kyoto in spring en-6093114c4c02, Japanese, week 3 en-6e7708b4e932.
Covers are Unsplash photos (covers.json: hotlinked, with their photographer), as the app's own picker stores them.
"""
import json, os, sys, datetime, uuid
out = sys.argv[1]
pages_dir = os.path.join(out, 'Workspace', 'pages')
os.makedirs(pages_dir, exist_ok=True)
now = datetime.datetime.now(datetime.timezone.utc)
def iso(dt): return dt.strftime('%Y-%m-%dT%H:%M:%S.000Z')

counter = [0]
def bid():
    counter[0] += 1
    return f'b{counter[0]:04d}'
def t(s, *marks):
    n = {'type': 'text', 'text': s}
    if marks: n['marks'] = [{'type': m} for m in marks]
    return n
def p(*inl): return {'type': 'paragraph', 'attrs': {'id': bid()}, 'content': list(inl)} if inl else {'type': 'paragraph', 'attrs': {'id': bid()}}
def h(level, s): return {'type': 'heading', 'attrs': {'id': bid(), 'level': level}, 'content': [t(s)]}
def bullets(*items): return {'type': 'bulletList', 'attrs': {'id': bid()}, 'content': [{'type': 'listItem', 'attrs': {'id': bid()}, 'content': [p(*(i if isinstance(i, list) else [t(i)]))]} for i in items]}
def tasks(*items): return {'type': 'taskList', 'attrs': {'id': bid()}, 'content': [{'type': 'taskItem', 'attrs': {'id': bid(), 'checked': done}, 'content': [p(t(s) if isinstance(s, str) else s)]} for s, done in items]}
def callout(icon, *blocks): return {'type': 'callout', 'attrs': {'id': bid(), 'icon': icon}, 'content': list(blocks)}
def toggle(summary, *blocks): return {'type': 'details', 'content': [{'type': 'detailsSummary', 'content': [t(summary)]}, {'type': 'detailsContent', 'content': list(blocks)}]}
def quote(*blocks): return {'type': 'blockquote', 'attrs': {'id': bid()}, 'content': list(blocks)}
def code(lang, s): return {'type': 'codeBlock', 'attrs': {'id': bid(), 'language': lang}, 'content': [t(s)]}
def math(latex): return {'type': 'blockMath', 'attrs': {'latex': latex}}
def ruby(base, reading): return {'type': 'ruby', 'attrs': {'reading': reading}, 'content': [t(base)]}
def table(rows):
    def cell(kind, s): return {'type': kind, 'content': [p(t(s))]}
    return {'type': 'table', 'content': [{'type': 'tableRow', 'content': [cell('tableHeader' if r == 0 else 'tableCell', c) for c in row]} for r, row in enumerate(rows)]}

def text_of(node):
    if node.get('type') == 'text': return node['text']
    if node.get('type') == 'blockMath': return node['attrs']['latex']
    return ''.join(text_of(c) for c in node.get('content', []))
def blocks_text(doc):
    lines = []
    def walk(n):
        kids = n.get('content', [])
        if n.get('type') in ('paragraph', 'heading', 'codeBlock', 'detailsSummary', 'blockMath'):
            lines.append(text_of(n)); return
        for k in kids: walk(k)
    walk(doc); return '\n'.join(lines)

def c(s, color=None, bg=None, *marks):
    attrs = {}
    if color: attrs['textColor'] = color
    if bg: attrs['bgColor'] = bg
    n = t(s, *marks)
    n.setdefault('marks', []).append({'type': 'textStyle', 'attrs': attrs})
    return n
def mention(pid, label): return {'type': 'mention', 'attrs': {'id': pid, 'label': label}}
def commented(s, thread):
    n = t(s)
    n['marks'] = [{'type': 'comment', 'attrs': {'id': thread}}]
    return n
def date(days, time=None, remind=None):
    """A date chip `days` from today (local), as "@" puts it — wall-clock time, a reminder `remind` minutes before."""
    day = (datetime.datetime.now() + datetime.timedelta(days=days)).strftime('%Y-%m-%d')
    return {'type': 'dateMention', 'attrs': {'id': str(uuid.uuid5(uuid.NAMESPACE_URL, f'hikki-demo/date/{days}/{time}')),
            'date': day, 'time': time, 'remind': remind, 'done': False, 'snoozed': None}}
def imath(latex): return {'type': 'inlineMath', 'attrs': {'latex': latex}}
def columns(*cols): return {'type': 'columns', 'content': [{'type': 'column', 'content': list(col)} for col in cols]}

files = []
COVERS = json.load(open(os.path.join(os.path.dirname(__file__), 'covers.json')))

def page(title, icon, blocks, parent=None, minutes_ago=60, cover=None, favorite=False, sort=0, locked=False):
    cover = COVERS.get(title, {}).get('url', cover)
    pid = 'en-' + uuid.uuid5(uuid.NAMESPACE_URL, 'hikki-demo/' + title).hex[:12]
    doc = {'type': 'doc', 'content': blocks or [p()]}
    edited = now - datetime.timedelta(minutes=minutes_ago)
    text = blocks_text(doc)
    f = {'format': 1, 'id': pid, 'title': title, 'icon': icon, 'cover': cover, 'parentId': parent, 'sortKey': float(sort),
         'createdAt': iso(edited - datetime.timedelta(days=3)), 'updatedAt': iso(edited), 'changedAt': iso(edited),
         'favoritedAt': iso(edited) if favorite else None, 'deletedAt': None, 'lockedAt': iso(edited) if locked else None,
         'plainText': text, 'wordCount': len(text.split()), 'content': doc}
    files.append(f); return pid

work = page('Work', '🗂️', [p(t('Projects, plans and the weekly review.'))], minutes_ago=600, sort=0)
page('Launch week', '📣', [
    callout('🗓️', p(t('Public beta goes out '), t('Thursday, November 20', 'bold'), t('. Plan in '), mention('en-f725dda9d6d5', 'Product launch'), t(', visuals in '), mention('en-8d64ef1034cc', 'Design notes'), t('.'))),
    p(t('The beta is for people that are keeping notes every day and that want them to stay on their own devices.')),
    columns(
        [h(3, 'Checklist'), tasks(('Freeze the build', True), ('Record the demo', True), ('Submit for review', False), ('Publish the site', False))],
        [h(3, 'Status'), bullets([t('Sync: '), c('testing', 'orange', 'orange')], [t('Search: '), c('done', 'green', 'green')], [t('Website: '), c('in review', 'blue', 'blue')], [t('Localization: '), c('blocked', 'red', 'red')])],
        [h(3, 'Budget'), p(t('Ads at '), imath(r'\$1{,}200'), t(' a week, for '), c('four weeks', None, 'yellow'), t(':')), math(r'4 \times 1200 = 4800')],
    ),
    columns(
        [h(3, 'Schedule'), table([['Day', 'What', 'Who'], ['Mon', 'Final build', 'Maya'], ['Tue', 'Press briefing', 'Leo'], ['Wed', 'Store review', 'Daniel'], ['Thu', 'Launch', 'Everyone']])],
        [h(3, 'Tokyo press kit'), p(ruby('新', 'あたら'), t('しいノート、'), ruby('筆記', 'ひっき'), t('。')), quote(p(t('Calm, fast, and yours.', 'italic'))), toggle('Open questions', bullets('Pricing after the beta', 'A second website language'))],
    ),
    code('swift', 'let launch = Date(year: 2026, month: 11, day: 20)\nprint(launch.formatted(date: .complete, time: .omitted))'),
], parent=work, minutes_ago=3, favorite=True, sort=-1)
page('Product launch', '🚀', [
    callout('🎯', p(commented('Ship the public beta to the App Store', 'thread-beta'), t(' by '), t('November 20', 'bold'), t('.'))),
    h(2, 'Milestones'),
    tasks(('Freeze the feature list', True), ('Finish onboarding screens', True), ('App Store screenshots', False), (commented('Press kit and website', 'thread-press'), False)),
    h(2, 'Owners'),
    table([['Area', 'Owner', 'Status'], ['Editor', 'Maya', 'Done'], ['Sync', 'Daniel', 'Testing'], ['Website', 'Leo', 'In progress']]),
    h(2, 'Open questions'),
    toggle('Pricing', p(t('Free with a one-time purchase for AI and sync to more devices.'))),
    toggle('Localization', p(t('English and Simplified Chinese at launch; Japanese next.'))),
], parent=work, minutes_ago=12, cover='gradient:ocean', favorite=True, sort=0)
page('Design notes', '✏️', [
    h(2, 'Spacing'),
    p(t('Every gap comes from the scale: 4, 8, 12, 16, 24, 32. Nothing in between.')),
    h(2, 'Motion'),
    p(t('One easing curve for everything that appears or leaves.')),
    code('swift', 'withAnimation(.spring(duration: 0.25, bounce: 0)) {\n    isOpen.toggle()\n}'),
    h(2, 'Line length'),
    p(t('Body text stays near 66 characters per line:')),
    math('\\text{width} \\approx 66 \\times 0.5\\,\\text{em}'),
], parent=work, minutes_ago=95, sort=1)
page('Weekly review', '🗓️', [
    h(2, 'Wins'),
    bullets('Search now finds text inside PDFs', 'Comments sync across devices'),
    h(2, 'Next week'),
    tasks(('Write the beta announcement', False), ('Review the onboarding copy', False)),
    p(t('Press briefing '), date(1, '15:00', 15), t(', the announcement goes out '), date(3, '09:30', 0), t('.')),
    p(t('Retro with the team '), date(5, None, 0), t('.')),
    quote(p(t('Make it work, make it right, make it fast.'))),
], parent=work, minutes_ago=300, sort=2)

personal = page('Personal', '🏡', [p(t('Trips, books and recipes.'))], minutes_ago=900, sort=1)
page('Kyoto in spring', '🌸', [
    p(t('Four days in late March, when the cherry trees open along the canals.')),
    h(2, 'Itinerary'),
    table([['Day', 'Morning', 'Afternoon'], ['1', 'Fushimi Inari', 'Gion walk'], ['2', "Philosopher's Path", 'Ginkaku-ji'], ['3', 'Arashiyama bamboo', 'Tenryu-ji'], ['4', 'Nishiki Market', 'Train home']]),
    h(2, 'Packing'),
    tasks(('Rail pass', True), ('Camera and spare battery', False), ('Comfortable shoes', False)),
], parent=personal, minutes_ago=40, cover='gradient:dusk', favorite=True, sort=0)
page('Reading list', '📚', [
    bullets([t('The Elements of Typographic Style', 'italic'), t(' — Robert Bringhurst')], [t('A Pattern Language', 'italic'), t(' — Christopher Alexander')], [t('The Design of Everyday Things', 'italic'), t(' — Don Norman')]),
    toggle('Finished this year', bullets('Piranesi', 'Klara and the Sun')),
], parent=personal, minutes_ago=200, sort=1)
recipes = page('Recipes', '🍳', [p(t('Weeknight dinners that take under thirty minutes.'))], parent=personal, minutes_ago=1500, sort=2)
page('Miso soup', '🍲', [
    h(2, 'Ingredients'),
    bullets('4 cups dashi', '3 tbsp white miso', '1 block silken tofu', '2 scallions'),
    h(2, 'Steps'),
    {'type': 'orderedList', 'attrs': {'id': bid(), 'start': 1}, 'content': [{'type': 'listItem', 'attrs': {'id': bid()}, 'content': [p(t(s))]} for s in ['Warm the dashi; do not let it boil.', 'Whisk the miso with a ladle of broth, then stir it back in.', 'Add the tofu and scallions just before serving.']]},
], parent=recipes, minutes_ago=1400, sort=0, locked=True)

page('Japanese, week 3', '🗾', [
    callout('📖', p(t('Readings sit above the kanji, as furigana. Select a word and press ⇧⌘R to add one.'))),
    h(2, 'Sentences'),
    p(ruby('毎日', 'まいにち'), ruby('日本語', 'にほんご'), t('を'), ruby('勉強', 'べんきょう'), t('しています。')),
    p(t('I study Japanese every day.', 'italic')),
    p(ruby('明日', 'あした'), t('は'), ruby('雨', 'あめ'), t('が'), ruby('降', 'ふ'), t('りそうです。')),
    p(t('It looks like it will rain tomorrow.', 'italic')),
    h(2, 'New words'),
    table([['Word', 'Meaning'], ['勉強 (べんきょう)', 'study'], ['天気 (てんき)', 'weather'], ['約束 (やくそく)', 'promise']]),
], minutes_ago=25, sort=2)
page('Ideas', '💡', [bullets('A calendar view for dated pages', 'Templates for meeting notes', 'Share a page as a web link')], minutes_ago=2000, sort=3)

for f in files:
    with open(os.path.join(pages_dir, f['id'] + '.json'), 'w') as fh:
        json.dump(f, fh, ensure_ascii=False, indent=2)

def write(path, value):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w') as fh:
        json.dump(value, fh, ensure_ascii=False, indent=2)

# Comments on Product launch: the two passages marked above, as PageComments keeps them.
launch_id = 'en-f725dda9d6d5'
def thread(tid, quote, minutes_ago, *comments):
    at = now - datetime.timedelta(minutes=minutes_ago)
    return {'id': tid, 'quote': quote, 'createdAt': iso(at)[:-5] + 'Z', 'updatedAt': iso(at)[:-5] + 'Z', 'comments': [
        {'id': f'{tid}-{i}', 'body': body, 'author': who, 'createdAt': iso(at + datetime.timedelta(minutes=i * 7))[:-5] + 'Z'}
        for i, (who, body) in enumerate(comments)]}
write(os.path.join(out, 'Workspace', 'comments', launch_id + '.json'), {'format': 1, 'pageId': launch_id, 'threads': [
    thread('thread-beta', 'Ship the public beta to the App Store', 90,
           ('Maya', 'Can we say "on iPhone, iPad and Mac" here? The beta is universal.'), ('Leo', 'Yes — I will update the press kit to match.')),
    thread('thread-press', 'Press kit and website', 40, ('Daniel', 'Screenshots for the site come from the demo workspace; I will send them by Friday.')),
]})

# Earlier versions of Design notes, as PageHistory keeps them: what Page History lists and compares word by word.
notes = next(f for f in files if f['title'] == 'Design notes')
def version(hours_ago, line_length):
    doc = json.loads(json.dumps(notes['content']))
    for i, block in enumerate(doc['content']):
        if block.get('type') == 'paragraph' and 'characters' in text_of(block):
            doc['content'][i] = p(t(line_length))
    saved = now - datetime.timedelta(hours=hours_ago)
    text = blocks_text(doc)
    stem = saved.strftime('%Y%m%dT%H%M%S.') + f'{saved.microsecond // 1000:03d}Z'
    write(os.path.join(out, 'Workspace', 'history', notes['id'], stem + '.json'), {
        'format': 1, 'pageId': notes['id'], 'savedAt': iso(saved)[:-5] + 'Z', 'device': 'MacBook Pro', 'reason': 'edit',
        'title': notes['title'], 'icon': notes['icon'], 'cover': None, 'plainText': text, 'wordCount': len(text.split()),
        'content': doc})
version(30, 'Lines of body text should be short.')
version(6, 'Body text stays under 80 characters a line, more or less.')
print(len(files), 'pages ->', pages_dir)
