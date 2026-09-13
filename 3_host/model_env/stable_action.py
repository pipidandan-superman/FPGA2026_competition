"""Decide once per new inference frame, never once per GUI refresh."""
import math

ACTION_CODES = {"Down": 1, "Stop": 4, "Thumbs Down": 5, "Thumbs up": 6, "Up": 7}


class StableAction:
    def __init__(self, confidence=0.75, frames=3, clear_seconds=1.0):
        if not 0 < confidence <= 1 or frames < 1 or clear_seconds <= 0:
            raise ValueError("Invalid stability thresholds")
        self.confidence, self.frames, self.clear_seconds = confidence, frames, clear_seconds
        self.last_fid = None
        self.last_arrival = float("-inf")
        self.last_valid = None
        self.candidate = None
        self.streak = 0
        self.published = 0
        self.started = None

    def feed(self, fid, arrival, now, detections):
        if self.started is None:
            self.started = now
        # Repeated frame IDs and older arrivals cannot extend or reset a streak.
        if fid == self.last_fid or arrival <= self.last_arrival:
            return self.tick(now)
        self.last_fid, self.last_arrival = fid, arrival
        labels = {d["label"] for d in detections}
        label = next(iter(labels)) if len(labels) == 1 else None
        confidence = max((d["confidence"] for d in detections), default=0)
        fresh = 0 <= now - arrival < self.clear_seconds
        if (not fresh or label not in ACTION_CODES or not math.isfinite(confidence)
                or confidence < self.confidence):
            self.candidate, self.streak = None, 0
            return self.tick(now)
        # Missing video for a full timeout also breaks consecutive inference evidence.
        if self.last_valid is not None and now - self.last_valid >= self.clear_seconds:
            self.candidate, self.streak = None, 0
        self.last_valid = now
        self.streak = self.streak + 1 if self.candidate == label else 1
        self.candidate = label
        code = ACTION_CODES[label]
        if self.streak >= self.frames and code != self.published:
            self.published = code
            return dict(action=code, label=label, fid=fid, confidence=confidence,
                        streak=self.streak, reason="stable")
        return None

    def tick(self, now):
        if self.started is None:
            self.started = now
        origin = self.last_valid if self.last_valid is not None else self.started
        if now - origin >= self.clear_seconds:
            self.candidate, self.streak = None, 0
            if self.published:
                self.published = 0
                return dict(action=0, label="CLEAR", reason="invalid_for_one_second")
        return None
