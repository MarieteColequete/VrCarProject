@tool
class_name AssetLibraryModel
extends RefCounted
## What the Asset Library pane shows, apart from drawing it: the models of the [AssetCatalogue],
## the chosen source (a pack, every pack, the favourites, or the recently placed), category, body
## type chips, and search, the favourites and recent models, each model's turn, and the view.
## [method to_dict] and [method from_dict] keep it between sessions. Nothing here calls the
## editor, so it is tested headless.
##
## The search matches every word, as part of a model's label, name, category, or pack; a word
## [code]pack:[/code], [code]cat:[/code], or [code]body:[/code] matches that field alone, as in
## [code]pack:trains body:vehicle tram[/code].

const ALL_PACKS := "*"
const FAVOURITES := "favourites"
const RECENT := "recent"
const ALL := ""
## The most recently placed models kept.
const RECENT_MAX := 20
const LOOKS_ONLY := "looks_only"
## The body type chips: a [BodyType] file's name, or [constant LOOKS_ONLY].
const KINDS: PackedStringArray = ["obstacle", "vehicle", "pavement", "looks_only"]
const GRID := "grid"
const LIST := "list"
const THUMB_MIN := 48
const THUMB_MAX := 160

var entries: Array[AssetCatalogue.Entry] = []
var packs: Array[AssetPack] = []
## The chosen source: [constant ALL_PACKS], [constant FAVOURITES], [constant RECENT], or a pack's
## title.
var source := ALL_PACKS
## The chosen category's title; [constant ALL] for every category.
var category := ALL
var query := ""
## The body type chips switched on; none switched on shows every kind.
var kinds := PackedStringArray()
var view := GRID
var thumb_size := 64
## Model paths marked as favourites.
var favourites := PackedStringArray()
## Model paths last placed, newest first.
var recent := PackedStringArray()
## Model path to the turn it was last placed with, radians.
var turns := {}

var _pack_counts := {}


## Takes the models of a scan, and counts them per pack.
func set_entries(p_entries: Array[AssetCatalogue.Entry]) -> void:
	entries = p_entries
	packs = AssetCatalogue.packs(entries)
	_pack_counts.clear()
	for entry in entries:
		_pack_counts[entry.pack] = _pack_counts.get(entry.pack, 0) + 1


func pack_count(pack: AssetPack) -> int:
	return _pack_counts.get(pack, 0)


## The models of the chosen source, before the category, chips, and search.
func in_source() -> Array[AssetCatalogue.Entry]:
	var out: Array[AssetCatalogue.Entry] = []
	if source == RECENT:
		for path in recent:
			var entry := find(path)
			if entry:
				out.append(entry)
		return out
	for entry in entries:
		if source == ALL_PACKS or (source == FAVOURITES and favourites.has(entry.path)) \
				or entry.pack.title == source:
			out.append(entry)
	return out


## The categories of the chosen source, in order, each with its count:
## [code][[title, count], ...][/code].
func categories() -> Array:
	var counts := {}
	var order: Array[String] = []
	for entry in in_source():
		if not counts.has(entry.category):
			order.append(entry.category)
		counts[entry.category] = counts.get(entry.category, 0) + 1
	return order.map(func(title: String) -> Array: return [title, counts[title]])


## The models shown: the chosen source's, in the chosen category, of the chips' kinds, matching
## the search.
func shown() -> Array[AssetCatalogue.Entry]:
	var words := search_words(query)
	var out: Array[AssetCatalogue.Entry] = []
	for entry in in_source():
		if category != ALL and entry.category != category:
			continue
		if not kinds.is_empty() and not kinds.has(kind_of(entry)):
			continue
		if matches(entry, words):
			out.append(entry)
	return out


## Whether anything narrows the models beyond the source.
func filtered() -> bool:
	return category != ALL or not kinds.is_empty() or not query.strip_edges().is_empty()


## Clears the category, chips, and search.
func clear_filters() -> void:
	category = ALL
	kinds = PackedStringArray()
	query = ""


## The chip [param entry] falls under: its body type's file name, or [constant LOOKS_ONLY].
static func kind_of(entry: AssetCatalogue.Entry) -> String:
	var body := entry.body()
	return body.resource_path.get_file().get_basename() if body else LOOKS_ONLY


## [param text] split into words, lower case: [code][field, word][/code], the field empty for a
## word matching any.
static func search_words(text: String) -> Array:
	var out: Array = []
	for word in text.to_lower().split(" ", false):
		var colon := word.find(":")
		var field := word.left(colon) if colon > 0 else ""
		if field in ["pack", "cat", "body"]:
			var value := word.substr(colon + 1)
			if not value.is_empty():
				out.append([field, value])
		else:
			out.append(["", word])
	return out


## Whether [param entry] matches every one of [param words].
static func matches(entry: AssetCatalogue.Entry, words: Array) -> bool:
	for pair: Array in words:
		var value: String = pair[1]
		var hit := false
		match pair[0]:
			"pack":
				hit = entry.pack.title.to_lower().contains(value) \
					or entry.pack.short_title().to_lower().contains(value)
			"cat":
				hit = entry.category.to_lower().contains(value)
			"body":
				hit = kind_of(entry).contains(value) or entry.body_title().to_lower().contains(value)
			_:
				hit = entry.label.to_lower().contains(value) \
					or entry.model_name.contains(value) \
					or entry.category.to_lower().contains(value) \
					or entry.pack.title.to_lower().contains(value)
		if not hit:
			return false
	return true


## The model at [param path]; null when it is not listed.
func find(path: String) -> AssetCatalogue.Entry:
	for entry in entries:
		if entry.path == path:
			return entry
	return null


## Marks [param path] as a favourite, or unmarks it; returns whether it is one now.
func toggle_favourite(path: String) -> bool:
	var at := favourites.find(path)
	if at >= 0:
		favourites.remove_at(at)
		return false
	favourites.append(path)
	return true


## Puts [param path] first among the recently placed models, keeping [constant RECENT_MAX].
func push_recent(path: String) -> void:
	var at := recent.find(path)
	if at >= 0:
		recent.remove_at(at)
	recent.insert(0, path)
	if recent.size() > RECENT_MAX:
		recent.resize(RECENT_MAX)


## The turn [param path] was last placed with, radians.
func turn_of(path: String) -> float:
	return float(turns.get(path, 0.0))


func set_turn(path: String, turn: float) -> void:
	if is_zero_approx(turn):
		turns.erase(path)
	else:
		turns[path] = turn


func to_dict() -> Dictionary:
	return {source = source, category = category, query = query, kinds = kinds, view = view,
		thumb_size = thumb_size, favourites = favourites, recent = recent, turns = turns}


## Restores what [method to_dict] gave, ignoring what is missing or of the wrong kind.
func from_dict(data: Dictionary) -> void:
	source = str(data.get("source", source))
	category = str(data.get("category", category))
	query = str(data.get("query", query))
	kinds = PackedStringArray(data.get("kinds", kinds))
	view = LIST if data.get("view", view) == LIST else GRID
	thumb_size = clampi(int(data.get("thumb_size", thumb_size)), THUMB_MIN, THUMB_MAX)
	favourites = PackedStringArray(data.get("favourites", favourites))
	recent = PackedStringArray(data.get("recent", recent))
	var saved: Variant = data.get("turns", {})
	turns = (saved as Dictionary).duplicate() if saved is Dictionary else {}
