# Cold Day - Project Status & Architecture (Prototype / MVP)

Cold Day is an innovative platform prototype designed for HVAC, refrigeration, electromechanical maintenance services, and on-demand technician dispatching (technician radar & bidding model).

---

## 1. Architecture Overview

The project is structured into two main components: a robust asynchronous Python backend (`backend/`) and a cross-platform Flutter client (`cold_day_flutter/`).

### Backend (`/backend`)
Built with **FastAPI**, **SQLAlchemy (Async)**, and **PostGIS** support.
- **`app/core/database.py`**: Manages async database engine sessions and base models.
- **`app/models/`**: SQLAlchemy ORM models representing domain entities (`EquipmentCategory`, `Equipment`, `ServiceRequest`, `Technician`, `TechnicianBid`).
- **`app/schemas/`**: Pydantic models for request validation and response serialization.
- **`app/api/`**: RESTful routers:
  - `catalog.py`: Data-driven service catalog (categories, technologies, residential/industrial sectors).
  - `services.py`: Service requests creation and spatial technician search.
  - `technicians.py`: Technician management and bidding endpoints.
- **`tests/`**: Comprehensive pytest test suite covering API endpoints, model updates, and schema validation.

### Frontend (`/cold_day_flutter`)
Built with **Flutter / Dart** using a **feature-first** architecture pattern.
- **`lib/core/`**: Core utilities, network clients (`api_client.dart`), and shared configurations.
- **`lib/features/`**: Self-contained feature modules:
  - `home/`: Main landing / dashboard navigation.
  - `request/`: Service request creation and confirmation flows.
  - `equipment/`: Equipment selection by category and sector.
  - `radar/`: Real-time technician radar view.
  - `technician/`: Technician dashboard and bid submission screen.
  - `auth/`, `pqr/`, `placeholder/`: Authentication, support/PQR, and coming soon modules.
- **`test/`**: Unit and widget tests mirroring the feature hierarchy.

---

## 2. Current Functionalities (MVP)

1. **Data-Driven Dynamic Catalog**:
   - Fetches categories (e.g., Refrigerators, Cold Rooms, Air Conditioning, Washing Machines, Electrical, Electronics, Camera Installation) directly from the backend, supporting conditional technologies (Conventional / Inverter) and sectors (Residential / Industrial).

2. **Geolocation & Technician Radar**:
   - Uses PostGIS spatial functions (`ST_DWithin`, `ST_Distance`) on the backend to locate nearby technicians within a specified radius from client coordinates.

3. **Service Requests & Bidding**:
   - Clients can submit service requests with location coordinates, equipment specifications, and offered budget.
   - Technicians can view nearby requests, submit counter-offers / bids (`price_offered`, `estimated_time_minutes`), and manage workflow status.

4. **Modular UI Screens**:
   - Complete navigation skeleton across client and technician roles, supporting interactive testing and prototyping.

---

## 3. Prototype Roadmap & Next Steps

- **State Management**: Integrate a reactive state management solution (such as Riverpod or Bloc) across Flutter features.
- **Database Migrations**: Introduce Alembic for robust schema versioning.
- **Authentication & RBAC**: Implement JWT-based authentication separating Client, Technician, and Administrator roles.
- **Real-Time Updates**: Add WebSockets for live technician tracking and instant bidding notifications.
