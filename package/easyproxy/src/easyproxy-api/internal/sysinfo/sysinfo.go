package sysinfo

import (
	"os"
	"strconv"
	"strings"
	"sync"
	"time"
)

// CPU 使用率：后台每秒采一次 /proc/stat，取值时用最近两次差值，
// 不阻塞请求，口径与 api.sh 的 top 解析一致（user+sys）。
type cpuSampler struct {
	mu       sync.Mutex
	prevIdle uint64
	prevTot  uint64
	user     uint64
	sys      uint64
	idle     uint64
	ready    bool
}

var cpu = &cpuSampler{}

func init() {
	go func() {
		cpu.tick()
		sampleOnce()
		for {
			time.Sleep(time.Second)
			sampleOnce()
		}
	}()
}

func sampleOnce() {
	tot, idle, user, sys, ok := readStat()
	if !ok {
		return
	}
	cpu.mu.Lock()
	defer cpu.mu.Unlock()
	if cpu.ready && tot > cpu.prevTot {
		dTot := float64(tot - cpu.prevTot)
		dIdle := float64(idle - cpu.prevIdle)
		dBusy := dTot - dIdle
		if dTot > 0 {
			u := int(dBusy / dTot * 100)
			if u < 0 {
				u = 0
			}
			if u > 100 {
				u = 100
			}
			cpu.user = uint64(u)
			cpu.sys = 0
			cpu.idle = uint64(100 - u)
		}
	} else {
		cpu.user, cpu.sys, cpu.idle = user, sys, idle
	}
	cpu.prevTot = tot
	cpu.prevIdle = idle
	cpu.ready = true
}

func (c *cpuSampler) tick() {}

func readStat() (tot, idle, user, sys uint64, ok bool) {
	b, err := os.ReadFile("/proc/stat")
	if err != nil {
		return 0, 0, 0, 0, false
	}
	var line string
	for _, l := range strings.Split(string(b), "\n") {
		if strings.HasPrefix(l, "cpu ") {
			line = l
			break
		}
	}
	if line == "" {
		return 0, 0, 0, 0, false
	}
	fields := strings.Fields(line)[1:]
	var vals []uint64
	for _, f := range fields {
		v, _ := strconv.ParseUint(f, 10, 64)
		vals = append(vals, v)
	}
	if len(vals) < 4 {
		return 0, 0, 0, 0, false
	}
	for _, v := range vals {
		tot += v
	}
	idle = vals[3]
	if len(vals) > 4 {
		idle += vals[4] // iowait
	}
	user = vals[0]
	sys = vals[2]
	return tot, idle, user, sys, true
}

// CPU 返回 user/sys/idle/usage 四项，数据结构与 api.sh 的 cpu_json 一致。
func CPU() map[string]interface{} {
	cpu.mu.Lock()
	defer cpu.mu.Unlock()
	return map[string]interface{}{
		"user":  cpu.user,
		"sys":   cpu.sys,
		"idle":  cpu.idle,
		"usage": cpu.user + cpu.sys,
	}
}

// Mem 返回 total_mb / used_mb / pct，口径同 mem_json。
func Mem() map[string]interface{} {
	total, avail := readMem()
	if total == 0 {
		return map[string]interface{}{"total_mb": 0, "used_mb": 0, "pct": 0}
	}
	pct := int((total - avail) * 100 / total)
	return map[string]interface{}{
		"total_mb": total / 1024,
		"used_mb":  (total - avail) / 1024,
		"pct":      pct,
	}
}

func readMem() (total, avail uint64) {
	b, err := os.ReadFile("/proc/meminfo")
	if err != nil {
		return 0, 0
	}
	for _, l := range strings.Split(string(b), "\n") {
		f := strings.Fields(l)
		if len(f) < 2 {
			continue
		}
		v, _ := strconv.ParseUint(f[1], 10, 64)
		switch f[0] {
		case "MemTotal:":
			total = v
		case "MemAvailable:":
			avail = v
		}
	}
	return total, avail
}

// Uptime 系统运行秒数。
func Uptime() int64 {
	b, err := os.ReadFile("/proc/uptime")
	if err != nil {
		return 0
	}
	f := strings.Fields(string(b))
	if len(f) == 0 {
		return 0
	}
	v, _ := strconv.ParseFloat(f[0], 64)
	return int64(v)
}
