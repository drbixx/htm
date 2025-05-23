# PL/SQL Hierarchical Triangular Mesh (HTM) Implementation

## 1. Introduction

This document provides an overview and usage guide for the PL/SQL implementation of the Hierarchical Triangular Mesh (HTM), a system for spatial indexing on a sphere. HTM allows for efficient querying of astronomical data, geographic information, or any other data associated with points or regions on a spherical surface.

This implementation is a PL/SQL port inspired by existing C++ HTM libraries, aiming to provide similar core functionalities within an Oracle Database environment. It enables spatial queries directly in SQL and PL/SQL, leveraging custom object types and packages.

Key features include:
*   Conversion between celestial coordinates (Right Ascension, Declination) and 3D Cartesian vectors.
*   Hierarchical subdivision of the sphere into spherical triangles (nodes).
*   Lookup of HTM IDs for given points.
*   Retrieval of geometric information (center, vertices) for HTM IDs.
*   Spatial intersection queries for circular regions and convex polygons, returning lists of HTM ID ranges.

## 2. System Architecture

The PL/SQL HTM system is organized into several packages and a set of SQL object types.

**SQL Object and Collection Types:**

These types define the fundamental data structures used throughout the system. They are typically defined in `htm_types.sql` (or individual files like `HTM_VECTOR_spec.sql`, `HTM_VECTOR_body.sql`, etc., if generated that way).

*   `HTM_NUMBER_LIST`: A collection type for storing lists of numbers.
*   `HTM_VECTOR`: Represents a 3D Cartesian vector or a an RA/Dec coordinate pair.
*   `HTM_VERTEX_LIST`: A collection of `HTM_VECTOR` objects, typically used for lists of vertices.
*   `HTM_ID_RANGE`: Represents a range of HTM IDs (low_id, high_id).
*   `HTM_ID_RANGE_LIST`: A collection of `HTM_ID_RANGE` objects.
*   `HTM_NODE`: Represents a node (spherical triangle) in the HTM hierarchy. Contains information like its ID, parent ID, level, children IDs, and vertex indices.
*   `HTM_NODE_LIST`: A collection of `HTM_NODE` objects.
*   `HTM_LAYER_INFO`: Stores metadata about each pre-built layer in the HTM structure.
*   `HTM_LAYER_LIST`: A collection of `HTM_LAYER_INFO` objects.

**PL/SQL Packages:**

*   **`HTM_GEOMETRY_UTILS`**:
    *   **Role:** Provides fundamental geometric calculations and HTM ID/name conversions.
    *   **Responsibilities:** Cartesian vector operations (magnitude, normalization, dot/cross product), conversion between Cartesian and RA/Dec coordinates, checking if a point is inside a spherical triangle, calculating spherical triangle area, and converting between numeric HTM IDs and their string representations (e.g., "N310").
    *   The body for `HTM_VECTOR` methods is also typically included in `htm_vector_body.sql` or associated with the type definition files and should be compiled before this package body.

*   **`HTM_INDEX_CORE`**:
    *   **Role:** Manages the core HTM index structure and operations.
    *   **Responsibilities:** Building the initial HTM tree up to a specified `build_level`, storing node and vertex information, retrieving node vertices (even for nodes deeper than the pre-built level), finding the HTM ID for a given point at a target level, and calculating the geometric center of an HTM triangle.

*   **`HTM_RANGE_UTILS`**:
    *   **Role:** Provides utilities for managing lists of HTM ID ranges.
    *   **Responsibilities:** Creating, adding to, and merging `HTM_ID_RANGE_LIST` collections. Ensures that range lists are kept sorted and non-overlapping. Also provides functions to check if an ID falls within a list of ranges and to get the count of ranges.

*   **`HTM_QUERY_INTERFACE`**:
    *   **Role:** Implements the logic for spatial intersection queries.
    *   **Responsibilities:** Determining which HTM triangles at a given query level intersect with specified geometric shapes (circles, convex polygons). It uses a recursive approach, checking triangles for full containment, full exclusion, or partial intersection, and subdividing partial intersections until the query level is reached.

*   **`HTM_SQL_API`**:
    *   **Role:** Provides a user-friendly SQL interface to the HTM system.
    *   **Responsibilities:** Exposing core HTM functionalities as SQL-callable procedures and functions. This includes system initialization, point-to-ID lookups, ID-to-point conversions, and pipelined table functions for circle and polygon intersection queries that return sets of `HTM_ID_RANGE` objects.

## 3. Setup and Compilation

To use the PL/SQL HTM system, the various SQL and PL/SQL files must be compiled in the correct order in your Oracle schema.

**Compilation Order:**

1.  **Object Types and Collection Types (e.g., `htm_types.sql`):**
    *   `HTM_NUMBER_LIST` (if defined in `htm_types.sql`, it should be early in this file)
    *   `HTM_VECTOR` (spec and body)
    *   `HTM_VERTEX_LIST`
    *   `HTM_ID_RANGE` (spec and body)
    *   `HTM_ID_RANGE_LIST`
    *   `HTM_NODE` (spec and body - depends on `HTM_NUMBER_LIST`)
    *   `HTM_NODE_LIST`
    *   `HTM_LAYER_INFO` (spec and body)
    *   `HTM_LAYER_LIST`
    *   *(If `HTM_VECTOR` body is in a separate `htm_vector_body.sql`, compile it after its spec and before `HTM_GEOMETRY_UTILS` body).*

2.  **`HTM_GEOMETRY_UTILS` Package:**
    *   `htm_geometry_utils_spec.sql`
    *   `htm_geometry_utils_body.sql`

3.  **`HTM_INDEX_CORE` Package:**
    *   `htm_index_core_spec.sql`
    *   `htm_index_core_body.sql`

4.  **`HTM_RANGE_UTILS` Package:**
    *   `htm_range_utils_spec.sql`
    *   `htm_range_utils_body.sql`

5.  **`HTM_QUERY_INTERFACE` Package:**
    *   `htm_query_interface_spec.sql`
    *   `htm_query_interface_body.sql`

6.  **`HTM_SQL_API` Package:**
    *   `htm_sql_api_spec.sql`
    *   `htm_sql_api_body.sql`

**One-Time System Initialization:**

After all packages are compiled, the HTM system needs to be initialized once per session or as needed if the configuration changes. This is done by calling a procedure from the `HTM_SQL_API` package:

```sql
BEGIN
  HTM_SQL_API.initialize_htm_system(
    p_build_level => 6,  -- Example build level
    p_query_level => 10  -- Example query level
  );
END;
/
```

*   `p_build_level` (NUMBER): Specifies the depth to which the HTM tree is pre-built and its nodes stored in memory (within PL/SQL collections). A higher build level means more nodes are pre-calculated, potentially speeding up queries that fall within this level, but increases initialization time and memory usage. Common values might range from 0 to 10.
*   `p_query_level` (NUMBER): Specifies the maximum depth to which queries can be resolved. This can be deeper than `p_build_level`. Nodes between `p_build_level` and `p_query_level` are calculated dynamically during queries. Common values might range up to 20-25, depending on the desired angular resolution.

The build and query levels defined during initialization are stored in global variables within `HTM_INDEX_CORE` and affect subsequent operations.

## 4. Data Types

### Object Types

*   **`HTM_VECTOR`**
    *   **Purpose:** Represents a 3D Cartesian vector (x, y, z) or a spherical coordinate pair (Right Ascension, Declination). When used for RA/Dec, typically `x` stores RA and `y` stores Dec.
    *   **Attributes:**
        *   `x` (NUMBER): Cartesian x-coordinate or Right Ascension.
        *   `y` (NUMBER): Cartesian y-coordinate or Declination.
        *   `z` (NUMBER): Cartesian z-coordinate (often 1.0 or radius for RA/Dec representations after conversion, or ignored if input is RA/Dec).
    *   **Key Constructors:**
        *   `HTM_VECTOR(x_val NUMBER, y_val NUMBER, z_val NUMBER)`: Creates a Cartesian vector.
        *   `HTM_VECTOR(ra NUMBER, dec NUMBER)`: Creates a normalized Cartesian vector from spherical RA/Dec coordinates. Input RA/Dec are in degrees.

*   **`HTM_ID_RANGE`**
    *   **Purpose:** Represents a contiguous range of HTM IDs.
    *   **Attributes:**
        *   `low_id` (NUMBER): The lower bound of the HTM ID range (inclusive).
        *   `high_id` (NUMBER): The upper bound of the HTM ID range (inclusive).
    *   **Key Constructors:**
        *   `HTM_ID_RANGE(l_id NUMBER, h_id NUMBER)`

*   **`HTM_NODE`**
    *   **Purpose:** Represents a single spherical triangle (node) in the HTM hierarchy.
    *   **Attributes:**
        *   `node_id` (NUMBER): Unique identifier for the node.
        *   `parent_id` (NUMBER): ID of the parent node.
        *   `level_num` (NUMBER): Depth of the node in the HTM tree (0 for root triangles).
        *   `is_leaf` (NUMBER): Flag (0 or 1) indicating if the node is a leaf in the pre-built tree.
        *   `children_ids` (HTM_NUMBER_LIST): List of IDs for the four child nodes.
        *   `v_ids` (HTM_NUMBER_LIST): List of three 0-indexed integers referencing vertices in the global `g_vertices` list in `HTM_INDEX_CORE`.
        *   `w_ids` (HTM_NUMBER_LIST): (Potentially used for midpoint vertex IDs, though current implementation primarily uses `v_ids` and calculates midpoints on the fly).
    *   **Key Constructors:**
        *   `HTM_NODE(p_node_id NUMBER, p_parent_id NUMBER, ...)`

*   **`HTM_LAYER_INFO`**
    *   **Purpose:** Stores metadata for each pre-built layer of the HTM.
    *   **Attributes:**
        *   `level_num` (NUMBER): The level number this information pertains to.
        *   `n_nodes` (NUMBER): Number of nodes in this layer.
        *   `n_vertices` (NUMBER): Cumulative number of unique vertices up to and including this layer.
        *   `n_edges` (NUMBER): Number of edges in this layer (typically `n_nodes` * 3).
        *   `first_node_id` (NUMBER): The ID of the first node created in this layer.
        *   `first_vertex_id` (NUMBER): The 0-indexed reference in `g_vertices` for the first new vertex added at this layer.
    *   **Key Constructors:**
        *   `HTM_LAYER_INFO(p_level_num NUMBER, ...)`

### Collection Types

*   **`HTM_NUMBER_LIST`**: `TABLE OF NUMBER`
    *   A collection type for storing lists of numbers, used internally by `HTM_NODE` for attributes like `children_ids`, `v_ids`, and `w_ids`.
*   **`HTM_VERTEX_LIST`**: `TABLE OF HTM_VECTOR`
    *   Used for lists of vertices, such as the vertices of a polygon or the global vertex list.
*   **`HTM_ID_RANGE_LIST`**: `TABLE OF HTM_ID_RANGE`
    *   Used to store lists of HTM ID ranges, typically as the result of intersection queries.
*   **`HTM_NODE_LIST`**: `TABLE OF HTM_NODE`
    *   Used for lists of HTM nodes.
*   **`HTM_LAYER_LIST`**: `TABLE OF HTM_LAYER_INFO`
    *   Used to store information about each pre-built layer in the HTM.

## 5. `HTM_SQL_API` - User Guide

This package provides the primary interface for interacting with the HTM system via SQL.

---

**`PROCEDURE initialize_htm_system(p_build_level NUMBER, p_query_level NUMBER)`**

*   **Description:** Initializes or re-initializes the HTM system with specified build and query levels. This procedure populates the internal HTM tree structure. It should be called once per session or when the desired HTM resolution changes.
*   **Parameters:**
    *   `p_build_level` (NUMBER, IN): The depth to which the HTM tree is pre-built and stored. Must be non-negative.
    *   `p_query_level` (NUMBER, IN): The maximum depth for HTM ID lookups and query resolution. Must be non-negative and typically greater than or equal to `p_build_level`.
*   **Return Value:** None.
*   **Example SQL Usage:**
    ```sql
    BEGIN
      HTM_SQL_API.initialize_htm_system(p_build_level => 7, p_query_level => 12);
    END;
    /
    ```
*   **Error Codes/Exceptions:**
    *   `-20300`: If `p_build_level` or `p_query_level` is null.
    *   `-20301`: If `p_build_level` or `p_query_level` is negative.
    *   Other errors may propagate from `HTM_INDEX_CORE.initialize_htm`.

---

**`FUNCTION lookup_htm_id(p_ra NUMBER, p_dec NUMBER, p_target_level NUMBER) RETURN NUMBER`**

*   **Description:** Finds the HTM ID at the specified `p_target_level` that contains the given celestial coordinates.
*   **Parameters:**
    *   `p_ra` (NUMBER, IN): Right Ascension of the point, in degrees. Range: 0-360.
    *   `p_dec` (NUMBER, IN): Declination of the point, in degrees. Range: -90 to +90.
    *   `p_target_level` (NUMBER, IN): The desired HTM level for the ID. Must be non-negative and not exceed the `g_max_query_level` set during initialization.
*   **Return Value:** (NUMBER) The HTM ID at `p_target_level` containing the point.
*   **Example SQL Usage:**
    ```sql
    SELECT HTM_SQL_API.lookup_htm_id(185.4, 23.5, 10) AS htm_id FROM DUAL;
    ```
*   **Error Codes/Exceptions:**
    *   `-20310`: If any input parameter is null.
    *   `-20311`: If `p_target_level` is out of the valid range (0 to `g_max_query_level`).
    *   Errors from `HTM_INDEX_CORE.id_by_point` may propagate (e.g., point not found in any base triangle, which is unlikely for valid RA/Dec).

---

**`FUNCTION get_htm_point_radec(p_htm_id NUMBER) RETURN VARCHAR2`**

*   **Description:** Calculates the geometric center of the specified HTM ID and returns its Right Ascension and Declination as a comma-separated string.
*   **Parameters:**
    *   `p_htm_id` (NUMBER, IN): The HTM ID for which to find the center point.
*   **Return Value:** (VARCHAR2) A string in the format "RA,DEC" (e.g., "185.432,23.512").
*   **Example SQL Usage:**
    ```sql
    SELECT HTM_SQL_API.get_htm_point_radec(12345) AS radec_center FROM DUAL;
    ```
*   **Error Codes/Exceptions:**
    *   `-20320`: If `p_htm_id` is null.
    *   `-20321`: If the Cartesian point for the HTM ID cannot be determined.
    *   `-20322`: If the Cartesian point cannot be converted to RA/Dec.
    *   Errors from `HTM_INDEX_CORE.point_by_id` or `HTM_GEOMETRY_UTILS.cartesian_to_ra_dec` may propagate.

---

**`FUNCTION get_htm_point_cartesian(p_htm_id NUMBER) RETURN HTM_VECTOR`**

*   **Description:** Calculates and returns the 3D Cartesian vector representing the geometric center of the specified HTM ID. The vector is normalized (unit length).
*   **Parameters:**
    *   `p_htm_id` (NUMBER, IN): The HTM ID.
*   **Return Value:** (`HTM_VECTOR`) The normalized 3D Cartesian vector of the HTM triangle's center.
*   **Example SQL Usage:**
    ```sql
    DECLARE
      center_vec HTM_VECTOR;
    BEGIN
      center_vec := HTM_SQL_API.get_htm_point_cartesian(12345);
      DBMS_OUTPUT.PUT_LINE('Center: (' || center_vec.x || ',' || center_vec.y || ',' || center_vec.z || ')');
    END;
    /
    ```
*   **Error Codes/Exceptions:**
    *   `-20330`: If `p_htm_id` is null.
    *   Errors from `HTM_INDEX_CORE.point_by_id` may propagate.

---

**`FUNCTION htm_circle_intersect(p_ra NUMBER, p_dec NUMBER, p_radius_degrees NUMBER, p_query_level NUMBER) RETURN HTM_ID_RANGE_LIST PIPELINED`**

*   **Description:** Finds all HTM ID ranges at the specified `p_query_level` that intersect with a given circular region on the sphere. This is a pipelined table function.
*   **Parameters:**
    *   `p_ra` (NUMBER, IN): Right Ascension of the circle's center, in degrees (0-360).
    *   `p_dec` (NUMBER, IN): Declination of the circle's center, in degrees (-90 to +90).
    *   `p_radius_degrees` (NUMBER, IN): Radius of the circle, in degrees. Must be non-negative.
    *   `p_query_level` (NUMBER, IN): The HTM level at which to find intersecting ID ranges. Must be non-negative and not exceed `g_max_query_level`.
*   **Return Value:** (TABLE OF `HTM_ID_RANGE`) A collection of `HTM_ID_RANGE` objects. Each object has `low_id` and `high_id` attributes.
*   **Example SQL Usage:**
    ```sql
    SELECT low_id, high_id
    FROM TABLE(HTM_SQL_API.htm_circle_intersect(
        p_ra => 10.5,
        p_dec => -20.0,
        p_radius_degrees => 1.5,
        p_query_level => 8
    ));
    ```
*   **Error Codes/Exceptions:**
    *   `-20340`: If any input parameter is null.
    *   `-20341`: If `p_query_level` is out of range.
    *   Errors from `HTM_QUERY_INTERFACE.circle_region_intersect` may propagate (e.g., radius < 0, invalid levels).

---

**`FUNCTION htm_polygon_intersect(p_vertices_ra_dec_string VARCHAR2, p_query_level NUMBER, p_delimiter CHAR DEFAULT ';') RETURN HTM_ID_RANGE_LIST PIPELINED`**

*   **Description:** Finds all HTM ID ranges at the specified `p_query_level` that intersect with a given convex polygon on the sphere. The polygon is defined by a string of RA/Dec vertex coordinates. This is a pipelined table function.
*   **Parameters:**
    *   `p_vertices_ra_dec_string` (VARCHAR2, IN): A string containing the polygon's vertices. Vertices are pairs of "RA,Dec" (in degrees), and these pairs are separated by `p_delimiter`. Example: "ra1,dec1;ra2,dec2;ra3,dec3". The polygon must be convex and vertices should be ordered (e.g., counter-clockwise).
    *   `p_query_level` (NUMBER, IN): The HTM level for intersection. Must be non-negative and not exceed `g_max_query_level`.
    *   `p_delimiter` (CHAR, IN, Optional): The character used to separate "RA,Dec" pairs in `p_vertices_ra_dec_string`. Defaults to ';'.
*   **Return Value:** (TABLE OF `HTM_ID_RANGE`) A collection of `HTM_ID_RANGE` objects.
*   **Example SQL Usage:**
    ```sql
    SELECT low_id, high_id
    FROM TABLE(HTM_SQL_API.htm_polygon_intersect(
        p_vertices_ra_dec_string => '10,5; 12,5; 12,7; 10,7', -- A small square
        p_query_level => 9
    ));

    SELECT low_id, high_id
    FROM TABLE(HTM_SQL_API.htm_polygon_intersect(
        p_vertices_ra_dec_string => '20.0,30.0|20.5,30.0|20.5,30.5|20.0,30.5',
        p_query_level => 10,
        p_delimiter => '|'
    ));
    ```
*   **Error Codes/Exceptions:**
    *   `-20350`: If `p_vertices_ra_dec_string` or `p_query_level` is null.
    *   `-20351`: If `p_query_level` is out of range.
    *   `-20352`: If `p_vertices_ra_dec_string` is empty.
    *   `-20353`: If an "RA,Dec" pair in the string is malformed (e.g., missing comma).
    *   `-20354`: If RA or Dec cannot be converted to a number.
    *   `-20355`: If fewer than 3 vertices are parsed from the string.
    *   Errors from `HTM_QUERY_INTERFACE.convex_hull_intersect` may propagate.

## 6. Core Packages Overview (For Advanced Users/Developers)

While most users will interact with the system via `HTM_SQL_API`, developers extending or maintaining the system may need to understand the roles of the underlying core packages.

*   **`HTM_GEOMETRY_UTILS`**:
    *   **Purpose:** Foundation for all geometric operations.
    *   **Key Functions:** `HTM_VECTOR` methods (constructors, `magnitude`, `normalize`, `dot_product`, `cross_product`), `cartesian_to_ra_dec`, `angle_between`, `is_inside_triangle`, `spherical_triangle_area`, `id_to_name`, `name_to_id`, `get_triangle_vertices_from_parent`.
    *   It encapsulates low-level geometric calculations on spherical triangles and vectors, as well as conversions between different HTM ID representations.

*   **`HTM_INDEX_CORE`**:
    *   **Purpose:** Manages the in-memory representation and construction of the HTM index.
    *   **Key Procedures/Functions:** `initialize_htm`, `make_new_layer` (private), `get_node_vertices`, `get_node_info`, `id_by_point`, `point_by_id`.
    *   This package handles the recursive subdivision of the sphere into triangles, stores the vertex and node information for pre-built levels, and can dynamically compute information for deeper levels. It uses global PL/SQL collections (`g_nodes`, `g_vertices`, `g_layers`) to store the index structure.

*   **`HTM_RANGE_UTILS`**:
    *   **Purpose:** Efficiently manages lists of HTM ID ranges.
    *   **Key Procedures/Functions:** `create_empty_range_list`, `add_range`, `merge_ranges`, `is_id_in_ranges`, `range_list_to_string`, `get_range_count`.
    *   Crucial for query results, as HTM intersections often yield multiple disjoint or overlapping ID ranges that need to be consolidated into a minimal, sorted list.

*   **`HTM_QUERY_INTERFACE`**:
    *   **Purpose:** Implements the spatial intersection logic against the HTM index.
    *   **Key Procedures/Functions:** `circle_region_intersect_cartesian`, `convex_hull_intersect_cartesian`, `check_triangle_circle_intersect_status` (private), `check_triangle_hull_intersect_status` (private), `intersect_node_recursive` (private).
    *   This package contains the algorithms to test HTM triangles (nodes) against query shapes (circles, polygons). It uses a recursive descent strategy: if a triangle is fully inside the shape, its ID (or range of descendant IDs) is added to the results; if fully outside, it's pruned; if partially intersecting, it's subdivided, and its children are tested.

## 7. Running Tests

A suite of PL/SQL test scripts is provided to verify the functionality of the HTM system. These scripts use `DBMS_OUTPUT` to report PASS/FAIL status for various test cases.

**Test Scripts:**
*   `test_geometry.sql`: Tests `HTM_VECTOR` and `HTM_GEOMETRY_UTILS`.
*   `test_core.sql`: Tests `HTM_INDEX_CORE`.
*   `test_ranges.sql`: Tests `HTM_RANGE_UTILS`.
*   `test_api.sql`: Tests `HTM_SQL_API`.

**Execution Steps:**

1.  **Compile all HTM code:** Ensure all object types, package specifications, and package bodies listed in the "Setup and Compilation" section are compiled successfully and in the correct order in your Oracle schema.
2.  **Connect to Oracle:** Use a tool like SQL*Plus or SQL Developer to connect to the schema where the HTM system is installed.
3.  **Enable Server Output:** Execute the following command in your SQL session to see the test results:
    ```sql
    SET SERVEROUTPUT ON SIZE UNLIMITED
    ```
4.  **Run Test Scripts:** Execute each test script file individually. For example, in SQL*Plus:
    ```sql
    @test_geometry.sql
    @test_core.sql
    @test_ranges.sql
    @test_api.sql
    ```
    *(Note: `test_core.sql` and `test_api.sql` will call `HTM_SQL_API.initialize_htm_system` as part of their setup.)*

**Interpreting Results:**

*   Each test case within the scripts will print a message starting with its description, followed by ": PASS" or ": FAIL".
*   Additional details may be printed for failed tests, such as expected vs. actual values.
*   If a script encounters a major PL/SQL error, the error message and potentially a backtrace will be displayed. Review these to identify issues in the underlying code or test logic.

These tests cover various aspects of the system, from basic geometric calculations and range management to complex spatial queries. Successful completion of these tests provides a good indication that the HTM system is functioning correctly.
```
