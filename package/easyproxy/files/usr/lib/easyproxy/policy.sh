#!/bin/sh
# Policy grouping (13 fixed business groups).
#
# The region-keyword groups built by `ep_node_region` are untouched; this file
# adds a second, operator-assigned layer on top:
#
#   - 13 groups exist for the life of the install and cannot be added or removed
#   - a node carries no group membership until it is bound explicitly, so a
#     subscription refresh never silently re-files nodes by their name
#   - one node may sit in several groups at once
#   - every group owns its own rule set: a built-in domain list (compiled in,
#     no download needed at boot) plus operator additions
#
# Storage stays in uci so `uci show easyproxy`, backup and restore keep working:
#
#   config policy 'p_netflix'
#       option key 'netflix'
#       option label 'Netflix'
#       option mode 'urltest'        # urltest | selector | direct
#       option fallback 'other'
#       option builtin '1'
#       option sort '2'
#       option nodes 'hk01 us02'     # uci section names, space separated
#
#   config policy_rule 'pr_netflix_1'
#       option policy 'netflix'
#       option type 'domain-suffix'  # domain | domain-suffix | domain-keyword | ip-cidr
#       option value '.netflix.com'

EP_POLICY_KEYS="speed netflix youtube tiktok ai disney google telegram apple games foreign china other"

# key|label|mode|fallback|builtin|sort   ("-" stands for an empty fallback;
# a literal empty field cannot be relied on once IFS is switched to "|")
ep_policy_defs() {
	printf '%s\n' \
		'speed|Speed|selector|-|0|1' \
		'netflix|Netflix|urltest|other|1|2' \
		'youtube|YouTube|urltest|other|1|3' \
		'tiktok|TikTok|urltest|other|1|4' \
		'ai|AI|urltest|other|1|5' \
		'disney|Disney+|urltest|other|1|6' \
		'google|Google|urltest|other|1|7' \
		'telegram|Telegram|urltest|other|1|8' \
		'apple|Apple|urltest|other|1|9' \
		'games|Games|urltest|other|1|10' \
		'foreign|国外|urltest|other|1|11' \
		'china|国内|direct|-|1|12' \
		'other|其他|selector|-|1|13'
}

# Built-in domains per group. Keep them small and stable: they are emitted
# inline so the engine starts without network access. Order matters only for
# reading; route priority comes from `sort`.
ep_policy_builtin_domains() {
	case "$1" in
		netflix)
			printf '%s\n' \
				'.netflix.com' '.netflix.net' '.nflxext.com' \
				'.nflximg.net' '.nflxvdiext.com' '.nflxvideo.net' \
				'.nflxso.net' '.netflixdnstest.com' '.fast.com' ;;
		youtube)
			printf '%s\n' \
				'.youtube.com' '.youtu.be' '.ytimg.com' '.yt3.ggpht.com' \
				'.googlevideo.com' '.youtubei.googleapis.com' \
				'.youtube-nocookie.com' '.youtubeeducation.com' ;;
		tiktok)
			printf '%s\n' \
				'.tiktok.com' '.tiktokv.com' '.tiktokcdn.com' \
				'.tiktokcdn-us.com' '.musical.ly' '.byteoversea.com' \
				'.ibytedtos.com' '.snssdk.com' '.tiktokd.org' ;;
		ai)
			printf '%s\n' \
				'.openai.com' '.chatgpt.com' '.oaistatic.com' '.oaiusercontent.com' \
				'.anthropic.com' '.claude.ai' '.perplexity.ai' '.poe.com' \
				'.midjourney.com' '.x.ai' '.groq.com' '.mistral.ai' \
				'.cohere.com' '.huggingface.co' '.replicate.com' ;;
		disney)
			printf '%s\n' \
				'.disneyplus.com' '.disney-plus.net' '.dssott.com' \
				'.bamgrid.com' '.disneystreaming.com' '.disney.com' ;;
		google)
			printf '%s\n' \
				'.google.com' '.googleapis.com' '.gstatic.com' \
				'.googleusercontent.com' '.gmail.com' '.googlemail.com' \
				'.blogger.com' '.blogspot.com' '.googleadservices.com' \
				'.googletagmanager.com' '.withgoogle.com' ;;
		telegram)
			printf '%s\n' \
				'.telegram.org' '.t.me' '.telegram.me' \
				'.telegram-cdn.org' '.tdesktop.com' '.telegra.ph' ;;
		apple)
			printf '%s\n' \
				'.apple.com' '.icloud.com' '.mzstatic.com' \
				'.apple-cloudkit.com' '.me.com' '.appstore.com' \
				'.itunes.com' '.appleid.apple.com' ;;
		games)
			printf '%s\n' \
				'.steamcommunity.com' '.steampowered.com' '.steamgames.com' \
				'.epicgames.com' '.battle.net' '.blizzard.com' \
				'.riotgames.com' '.leagueoflegends.com' '.playstation.com' \
				'.xboxlive.com' '.nintendo.com' '.ubisoft.com' \
				'.ea.com' '.origin.com' '.gog.com' ;;
		*) return 0 ;;
	esac
}

# Map a policy key onto its uci section name
ep_policy_section() {
	printf 'p_%s' "$1"
}

# Create any missing group section with its default options. Idempotent: an
# existing section keeps whatever the operator set, only missing options are
# filled in, so this is safe to call from every entry point.
ep_policy_ensure() {
	local key label mode fallback builtin sort section
	ep_policy_defs | while IFS='|' read -r key label mode fallback builtin sort; do
		[ -n "$key" ] || continue
		[ "$fallback" = "-" ] && fallback=""
		section="$(ep_policy_section "$key")"
		if ! uci -q get "easyproxy.$section" >/dev/null 2>&1; then
			uci -q set "easyproxy.$section=policy"
			uci -q set "easyproxy.$section.key=$key"
			uci -q set "easyproxy.$section.label=$label"
			uci -q set "easyproxy.$section.mode=$mode"
			uci -q set "easyproxy.$section.builtin=$builtin"
			uci -q set "easyproxy.$section.sort=$sort"
			[ -n "$fallback" ] && uci -q set "easyproxy.$section.fallback=$fallback"
		else
			# Backfill options introduced later without touching operator values.
			uci -q get "easyproxy.$section.key" >/dev/null 2>&1 || uci -q set "easyproxy.$section.key=$key"
			uci -q get "easyproxy.$section.label" >/dev/null 2>&1 || uci -q set "easyproxy.$section.label=$label"
			uci -q get "easyproxy.$section.mode" >/dev/null 2>&1 || uci -q set "easyproxy.$section.mode=$mode"
			uci -q get "easyproxy.$section.builtin" >/dev/null 2>&1 || uci -q set "easyproxy.$section.builtin=$builtin"
			# sort is the definition order, not an operator value: always keep it
			# in step with ep_policy_defs so an upgraded box reorders itself.
			uci -q set "easyproxy.$section.sort=$sort"
		fi
	done
	uci -q commit easyproxy
	return 0
}

ep_policy_get() {
	local section
	section="$(ep_policy_section "$1")"
	uci -q get "easyproxy.$section.$2" 2>/dev/null || printf '%s' "$3"
}

# Validate a policy key
ep_policy_key_valid() {
	case " $EP_POLICY_KEYS " in
		*" $1 "*) return 0 ;;
	esac
	return 1
}

# Print keys sorted by `sort`, then by key for stable tie-breaks
ep_policy_keys_sorted() {
	local key sort
	for key in $EP_POLICY_KEYS; do
		sort="$(ep_policy_get "$key" sort 99)"
		printf '%s %s\n' "$sort" "$key"
	done | sort -n -k1,1 -k2,2 | while read -r _ k; do printf '%s\n' "$k"; done
}

# space separated uci section names bound to a group
ep_policy_nodes() {
	ep_policy_get "$1" nodes ''
}

# Bind node sections to a group. Existing memberships are preserved; a node
# already in the group is not duplicated. Prints how many were added.
ep_policy_bind() {
	local key section current resolved added=0 want have tok
	key="$1"; shift
	ep_policy_key_valid "$key" || { ep_err "unknown policy: $key"; return 1; }
	section="$(ep_policy_section "$key")"
	current=" $(ep_policy_get "$key" nodes '') "
	for want in "$@"; do
		[ -n "$want" ] || continue
		if ! resolved="$(ep_node_resolve "$want")" || [ -z "$resolved" ]; then
			ep_err "unknown node: $want"
			return 1
		fi
		want="$resolved"
		have=0
		for tok in $current; do
			[ "$tok" = "$want" ] && have=1 && break
		done
		[ "$have" = "1" ] && continue
		current="$current$want "
		added=$((added + 1))
	done
	current="$(printf '%s' "$current" | tr -s ' ' ' ' | sed 's/^ //; s/ $//')"
	uci -q set "easyproxy.$section.nodes=$current"
	uci -q commit easyproxy
	printf '%s' "$added"
}

# Remove node sections from a group
ep_policy_unbind() {
	local key section current want tok keep out="" removed=0
	key="$1"; shift
	ep_policy_key_valid "$key" || { ep_err "unknown policy: $key"; return 1; }
	section="$(ep_policy_section "$key")"
	current="$(ep_policy_get "$key" nodes '')"
	for tok in $current; do
		keep=1
		for want in "$@"; do
			[ "$tok" = "$want" ] && keep=0 && break
		done
		[ "$keep" = "0" ] && removed=$((removed + 1)) && continue
		out="$out$tok "
	done
	out="$(printf '%s' "$out" | sed 's/ $//')"
	uci -q set "easyproxy.$section.nodes=$out"
	uci -q commit easyproxy
	printf '%s' "$removed"
}

# Is the policy layer in use at all? Any group with at least one member turns
# it on; until then the generated config keeps the legacy region-group layout.
ep_policy_active() {
	local key
	for key in $EP_POLICY_KEYS; do
		[ -n "$(ep_policy_nodes "$key")" ] && return 0
	done
	return 1
}

# Every node section bound to at least one group, space separated. Used by the
# probe scheduler so unassigned nodes are never tested.
ep_policy_all_bound_nodes() {
	local key seen="" tok
	for key in $EP_POLICY_KEYS; do
		for tok in $(ep_policy_nodes "$key"); do
			case " $seen " in *" $tok "*) continue ;; esac
			seen="$seen $tok"
		done
	done
	printf '%s' "${seen# }"
}

# Custom rules of one group, one per line as "type:value"
ep_policy_rules() {
	local key
	key="$1"
	uci -q show easyproxy 2>/dev/null | while IFS= read -r line; do
		case "$line" in
			easyproxy.pr_*=policy_rule) continue ;;
		esac
		printf '%s\n' "$line"
	done | awk -F'[.=]' -v want="$key" -v q="'" '
		{
			# easyproxy.pr_xxx.type='domain-suffix'
			sec = $2; opt = $3
			val = substr($0, index($0, "=") + 1)
			gsub("^" q, "", val)
			gsub(q "$", "", val)
			if (opt == "policy") pol[sec] = val
			else if (opt == "type") typ[sec] = val
			else if (opt == "value") vl[sec] = val
			}
			END {
				for (s in pol) if (pol[s] == want && typ[s] != "" && vl[s] != "")
					print typ[s] ":" vl[s]
			}'
}

ep_policy_rule_add() {
	local key="$1" type="$2" value="$3" section
	ep_policy_key_valid "$key" || { ep_err "unknown policy: $key"; return 1; }
	[ -n "$value" ] || { ep_err "empty rule value"; return 1; }
	case "$type" in
		domain|domain-suffix|domain-keyword|ip-cidr) ;;
		*) ep_err "rule type must be domain, domain-suffix, domain-keyword or ip-cidr"; return 1 ;;
	esac
	section="pr_$(printf '%s' "$key" | tr -cd 'a-z0-9')_$(date +%s)$(printf '%03d' $(( $$ % 1000 )))"
	uci -q set "easyproxy.$section=policy_rule"
	uci -q set "easyproxy.$section.policy=$key"
	uci -q set "easyproxy.$section.type=$type"
	uci -q set "easyproxy.$section.value=$value"
	uci -q commit easyproxy
	printf '%s' "$section"
}

ep_policy_rule_del() {
	local section="$1"
	case "$section" in
		pr_*) ;;
		*) ep_err "not a policy rule section: $section"; return 1 ;;
	esac
	uci -q delete "easyproxy.$section" || { ep_err "no such rule: $section"; return 1; }
	uci -q commit easyproxy
	return 0
}

# List the group's rules as JSON: [{"section":"..","type":"..","value":".."}]
ep_policy_rules_json() {
	local key first=1 pair type value
	key="$1"
	printf '['
	for pair in $(ep_policy_rules "$key"); do
		type="${pair%%:*}"; value="${pair#*:}"
		[ "$first" = "1" ] || printf ','
		first=0
		printf '{"type":"%s","value":"%s"}' "$(ep_json_escape "$type")" "$(ep_json_escape "$value")"
	done
	printf ']'
}

# Effective domains for one group: built-in list (unless switched off) plus
# operator rules of type domain-suffix / domain. Emitted as JSON array.
ep_policy_domains_json() {
	local key first=1 d
	key="$1"
	printf '['
	if [ "$(ep_policy_get "$key" builtin 1)" = "1" ]; then
		for d in $(ep_policy_builtin_domains "$key"); do
			[ "$first" = "1" ] || printf ','
			first=0
			printf '"%s"' "$(ep_json_escape "$d")"
		done
	fi
	for d in $(ep_policy_rules "$key" | sed -n 's/^domain-suffix://p; s/^domain://p'); do
		[ "$first" = "1" ] || printf ','
		first=0
		printf '"%s"' "$(ep_json_escape "$d")"
	done
	printf ']'
}

ep_policy_cidrs_json() {
	local key first=1 d
	key="$1"
	printf '['
	for d in $(ep_policy_rules "$key" | sed -n 's/^ip-cidr://p'); do
		[ "$first" = "1" ] || printf ','
		first=0
		printf '"%s"' "$(ep_json_escape "$d")"
	done
	printf ']'
}

# Node sections of one group as a JSON array of {"section","name"} objects
ep_policy_nodes_json() {
	local key first=1 n
	key="$1"
	printf '['
	for n in $(ep_policy_nodes "$key"); do
		[ "$first" = "1" ] || printf ','
		first=0
		printf '{"section":"%s","name":"%s"}' \
			"$(ep_json_escape "$n")" "$(ep_json_escape "$(ep_node_tag "$n")")"
	done
	printf ']'
}

# ---- shared probe cache -------------------------------------------------
#
# One probe per node no matter how many groups it belongs to, so a node bound
# to five groups is measured once. The TSV keeps what the renderer needs to
# apply the two stability rules:
#
#   section  state  ms  fails  smooth_ms
#
#   fails >= 3        -> quarantined, left out of every urltest member list
#                        until a later round succeeds again
#   |ms - smooth_ms|  -> smaller than EP_POLICY_SMOOTH_MS means the reading is
#                        carried over, so a single noisy sample cannot reorder
#                        the group
EP_POLICY_TEST_CACHE="${EP_POLICY_TEST_CACHE:-/tmp/easyproxy-policy-test.tsv}"
EP_POLICY_SMOOTH_MS="${EP_POLICY_SMOOTH_MS:-80}"
EP_POLICY_QUARANTINE="${EP_POLICY_QUARANTINE:-3}"

ep_policy_test_read() {
	local node="$1" field="$2"
	[ -r "$EP_POLICY_TEST_CACHE" ] || return 1
	awk -F'\t' -v n="$node" -v f="$field" '$1==n {print $f; found=1} END{if(!found) exit 1}' "$EP_POLICY_TEST_CACHE"
}

# Probe every node that belongs to at least one group and rewrite the cache
ep_policy_test_run() {
	local node probe state ms fails old_ms smooth
	local tmp="$EP_POLICY_TEST_CACHE.tmp"
	: > "$tmp" || return 1
	for node in $(ep_policy_all_bound_nodes); do
		probe="$(ep_node_probe "$node")"
		state="${probe%% *}"
		ms="${probe#* }"
		old_ms="$(ep_policy_test_read "$node" 5 2>/dev/null)"
		fails="$(ep_policy_test_read "$node" 4 2>/dev/null)"
		case "$fails" in ''|*[!0-9]*) fails=0 ;; esac
		if [ "$state" = "reachable" ]; then
			case "$ms" in ''|*[!0-9]*) ms="" ;; esac
			fails=0
			if [ -n "$ms" ] && [ -n "$old_ms" ]; then
				delta=$((ms - old_ms))
				[ "$delta" -lt 0 ] && delta=$((-delta))
				[ "$delta" -lt "$EP_POLICY_SMOOTH_MS" ] && ms="$old_ms"
			fi
			smooth="${ms:-$old_ms}"
		else
			fails=$((fails + 1))
			smooth="$old_ms"
		fi
		printf '%s\t%s\t%s\t%s\t%s\n' "$node" "$state" "${ms:--}" "$fails" "${smooth:--}" >> "$tmp"
	done
	mv "$tmp" "$EP_POLICY_TEST_CACHE"
}

# "state ms fails smooth_ms" for one node, all fields "-" when unknown
ep_policy_test_state() {
	local node="$1" state ms fails smooth
	state="$(ep_policy_test_read "$node" 2 2>/dev/null)"; state="${state:--}"
	ms="$(ep_policy_test_read "$node" 3 2>/dev/null)"; ms="${ms:--}"
	fails="$(ep_policy_test_read "$node" 4 2>/dev/null)"; fails="${fails:--}"
	smooth="$(ep_policy_test_read "$node" 5 2>/dev/null)"; smooth="${smooth:--}"
	printf '%s %s %s %s' "$state" "$ms" "$fails" "$smooth"
}

# Is the node quarantined (three consecutive failed rounds)?
ep_policy_node_quarantined() {
	local fails
	fails="$(ep_policy_test_read "$1" 4 2>/dev/null)"
	case "$fails" in ''|*[!0-9]*) return 1 ;; esac
	[ "$fails" -ge "$EP_POLICY_QUARANTINE" ]
}

# Member sections of a group that are eligible for an urltest outbound:
# bound, enabled and not quarantined
ep_policy_members() {
	local n
	for n in $(ep_policy_nodes "$1"); do
		[ "$(ep_get "$n" enabled 1)" = "1" ] || continue
		ep_policy_node_quarantined "$n" && continue
		printf '%s\n' "$n"
	done
}
