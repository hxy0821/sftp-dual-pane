#pragma once

#include <QElapsedTimer>
#include <QVector>

// 传输进度节流与测速：
//  · 采样按约 10Hz 节流（最小 100ms 间隔），避免 128KB/次的高频进度信号淹没 UI
//  · 速度 = 最近 2.5s 滑动窗口内的“字节数 / 时间”，天然平滑，不随瞬时抖动乱跳
//  · ETA = 剩余字节 / 窗口速度；传输完成时为 0，无法估计（速度为 0）时为 -1
class ProgressMeter
{
public:
    static const qint64 kWindowMs = 2500;         // 测速滑动窗口
    static const qint64 kEmitIntervalMs = 100;    // 进度发射最小间隔（约 10Hz）
    static const qint64 kSampleIntervalMs = 50;   // 采样归并间隔：更密的回调只更新末值
    static const int kMaxSamples = 128;           // 采样点上限（窗口/间隔=50，留足余量）

    void begin(qint64 totalBytes);        // 新任务开始：重置状态并开始计时
    bool sample(qint64 transferred);      // 记录采样；返回 true 表示本次应发射进度
    bool force(qint64 transferred);       // 忽略节流强制发射（任务结束时保证终值准确）

    double speed() const { return m_speedSmooth; }  // 字节/秒（显示用，已做跨点平滑）
    double eta() const { return m_eta; }            // 秒；-1 = 无法估计

private:
    void record(qint64 transferred);          // 追加一次采样（同毫秒内只更新末值）
    void compute(qint64 transferred);         // 基于滑动窗口重算速度与 ETA

    QElapsedTimer m_clock;
    QVector<qint64> m_ts;      // 采样时间点（相对 begin 的毫秒）
    QVector<qint64> m_bytes;   // 采样时的累计已传字节
    qint64 m_total = 0;
    qint64 m_latest = 0;   // 最新字节数（不等窗口采样，供 ETA / 终值使用）
    qint64 m_lastEmitMs = -1;
    double m_speed = 0.0;        // 窗口速度
    double m_speedSmooth = 0.0;  // 跨发射点指数平滑后的显示速度
    bool m_hasSpeed = false;
    double m_eta = -1.0;
};
