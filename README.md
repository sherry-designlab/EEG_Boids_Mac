# EEG_Boids_Mac

PC Version AffectiveSwarm application

MUSE 2（Mind Monitor → OSC 8000）の脳波から Arousal / Valence を求め、Boids と光絵（ライトペインティング）で可視化するシステム（Processing 4）。

## 実行
1. Processing 4 で `Modified_SplitScreen.pde` を開く（ライブラリ：oscP5）
2. Mind Monitor の OSC 送信先をこの Mac（ポート 8000）に設定
3. 実行 → キャリブレーション → Space キーで瞑想の記録開始 / 終了（記録中 M キーでマーク）

## データの保存場所
個人データはプログラムと別の場所に保存されます（このリポジトリには含まれません）：
`~/Documents/EEG_Boids_Mac_Data/`（sessions / artworks / cache / calibration.json / swarm_state.json / tags.json）

## 主な構成
- `SwarmSim.pde`：リアルタイム・再生・光絵で共通の Boids シミュレーション（仮想世界 1600×1000、固定ステップ、シード付き乱数）
- `LightPainting.pde` / `Artwork.pde`：光絵の成像と作品アーカイブ（1 セッション 1 枚、3840×2400）
- `Gallery.pde` / `Viewer.pde` / `Diary.pde`：ギャラリー、作品ビューア、メモ
- `Recording.pde` / `SessionIO.pde` / `CsvImport.pde` / `DataManager.pde`：記録、CSV、インポート、データ管理

変更履歴：`更新说明.txt`
