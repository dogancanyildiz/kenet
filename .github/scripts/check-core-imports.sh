#!/bin/sh
# Core paketi Apple arayüz ve sistem çerçevelerine bağımsızdır (AGENTS.md, değişmez kurallar).
# Linux derlemesi bunu zaten zorlar; bu denetim hatayı daha erken ve anlaşılır biçimde gösterir.
set -eu

forbidden='SwiftUI|UIKit|AppKit|EventKit|CoreLocation|WidgetKit|CloudKit'
pattern="^[[:space:]]*(@[A-Za-z_]+[[:space:]]+)*((public|package|internal|fileprivate|private)[[:space:]]+)?import[[:space:]]+((struct|class|enum|protocol|func|var|let|typealias)[[:space:]]+)?(${forbidden})([^A-Za-z0-9_]|\$)"

if matches=$(grep -rnE --include='*.swift' --exclude-dir='.build' "$pattern" Packages/Core); then
    echo "Core içinde yasak import bulundu:"
    echo "$matches"
    exit 1
fi

echo "Core içinde yasak import yok."
