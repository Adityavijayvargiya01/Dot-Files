function parse(raw) {
  try {
    var data = JSON.parse(raw || "[]")
    return Array.isArray(data) ? data.filter(function(d) {
      return d && typeof d.text === "string"
    }).map(function(d) {
      return {
        id: d.id,
        text: d.text,
        media: Array.isArray(d.media) ? d.media : [],
        updated: d.updated || 0
      }
    }) : []
  } catch (e) {
    return []
  }
}

function preview(text, limit) {
  var t = String(text || "").replace(/\s+/g, " ").replace(/^\s+|\s+$/g, "")
  if (!t) return "Empty draft"
  if (t.length <= limit) return t
  return t.slice(0, limit - 1) + "…"
}

function nextId() {
  return String(Date.now()) + "-" + String(Math.floor(Math.random() * 1000))
}

function upsert(list, id, text, media) {
  var body = String(text || "")
  var files = Array.isArray(media) ? media.slice() : []
  if (!body.replace(/^\s+|\s+$/g, "") && files.length === 0)
    return remove(list, id)
  var out = []
  var found = false
  for (var i = 0; i < list.length; i++) {
    if (list[i].id === id) {
      out.push({ id: id, text: body, media: files, updated: Date.now() })
      found = true
    } else {
      out.push(list[i])
    }
  }
  if (!found)
    out.unshift({ id: id || nextId(), text: body, media: files, updated: Date.now() })
  return out
}

function remove(list, id) {
  var out = []
  for (var i = 0; i < list.length; i++) {
    if (list[i].id !== id) out.push(list[i])
  }
  return out
}

function find(list, id) {
  for (var i = 0; i < list.length; i++) {
    if (list[i].id === id) return list[i]
  }
  return null
}
