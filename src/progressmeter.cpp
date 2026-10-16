#include "progressmeter.h"

void ProgressMeter::begin(qint64 totalBytes)
{
    m_total = totalBytes < 0 ? 0 : totalBytes;
    m_ts.clear();
    m_bytes.clear();
    m_latest = 0;
    m_speed = 0.0;
    m_speedSmooth = 0.0;
    m_hasSpeed = false;
    m_eta = -1.0;
    m_lastEmitMs = -1;
    m_clock.start();
}

void ProgressMeter::record(qint64 transferred)
{
    m_latest = transferred;
    const qint64 now = m_clock.isValid() ? m_clock.elapsed() : 0;
    if (m_bytes.isEmpty() || now - m_ts.last() >= kSampleIntervalMs) {
        // 距上一个采样点足够久：追加新采样点。
        // 注意：入窗口后的点不再回改——保证每个点都是“确切值 + 确切时间”，
        // 否则末点被滚动更新会让值与时间戳错位，造成系统性测速偏低。
        m_ts.append(now);
        m_bytes.append(transferred);
        while (m_bytes.size() > kMaxSamples) {
            m_ts.removeFirst();
            m_bytes.removeFirst();
        }
    }
    // 采样间隔内的密集回调只更新 m_latest（供 ETA / 进度使用）
}

void ProgressMeter::compute(qint64 transferred)
{
    m_latest = transferred;
    const qint64 now = m_clock.isValid() ? m_clock.elapsed() : 0;
    // 丢弃窗口外的旧采样点，但至少保留三个点用于计算（避免裁剪后只剩两个边界点）
    while (m_bytes.size() > 3 && now - m_ts.first() > kWindowMs) {
        m_ts.removeFirst();
        m_bytes.removeFirst();
    }
    if (m_bytes.size() < 3) {
        // 采样点不足（起步 <0.2s）：还没法平滑测速，先不报速度
        m_speed = 0.0;
        m_eta = -1.0;
        return;
    }
    const qint64 dt = m_ts.last() - m_ts.first();
    const qint64 db = qMax<qint64>(0, m_bytes.last() - m_bytes.first());
    if (dt <= 0) {
        m_speed = 0.0;
        m_eta = -1.0;
        return;
    }
    m_speed = double(db) * 1000.0 / double(dt);
    // 跨发射点再做一层指数平滑（时间常数约 300ms），显示数字更稳
    if (!m_hasSpeed) {
        m_speedSmooth = m_speed;
        m_hasSpeed = true;
    } else {
        m_speedSmooth = m_speedSmooth * 0.7 + m_speed * 0.3;
    }
    const qint64 remaining = m_total - m_latest;
    if (remaining <= 0)
        m_eta = 0.0;
    else if (m_speedSmooth > 0.0)
        m_eta = double(remaining) / m_speedSmooth;
    else
        m_eta = -1.0;
}

bool ProgressMeter::sample(qint64 transferred)
{
    record(transferred);
    const qint64 now = m_clock.isValid() ? m_clock.elapsed() : 0;
    if (m_lastEmitMs >= 0 && now - m_lastEmitMs < kEmitIntervalMs)
        return false;
    m_lastEmitMs = now;
    compute(transferred);
    return true;
}

bool ProgressMeter::force(qint64 transferred)
{
    record(transferred);
    m_lastEmitMs = m_clock.isValid() ? m_clock.elapsed() : 0;
    compute(transferred);
    return true;
}
