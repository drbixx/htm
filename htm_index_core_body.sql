CREATE OR REPLACE PACKAGE BODY HTM_INDEX_CORE AS

  -- Global Variables/State
  g_max_build_level NUMBER;
  g_max_query_level NUMBER;
  
  TYPE htm_node_assoc_array IS TABLE OF HTM_NODE INDEX BY PLS_INTEGER; -- Node_ID is the index
  g_nodes htm_node_assoc_array;
  
  g_vertices HTM_VERTEX_LIST := HTM_VERTEX_LIST();
  g_layers HTM_LAYER_LIST := HTM_LAYER_LIST();

  -- Private helper to add a vertex if it's new, returns its index
  FUNCTION add_vertex_if_new(v HTM_VECTOR, existing_vertices IN OUT NOCOPY HTM_VERTEX_LIST) RETURN PLS_INTEGER IS
    epsilon CONSTANT NUMBER := 0.0000000001; -- For comparing vectors
    idx PLS_INTEGER;
  BEGIN
    FOR i IN 1 .. existing_vertices.COUNT LOOP
      -- Check if vertex already exists (within epsilon)
      IF (ABS(existing_vertices(i).x - v.x) < epsilon AND
          ABS(existing_vertices(i).y - v.y) < epsilon AND
          ABS(existing_vertices(i).z - v.z) < epsilon)
      THEN
        RETURN i - 1; -- 0-indexed
      END IF;
    END LOOP;
    -- If not found, add it
    existing_vertices.EXTEND;
    existing_vertices(existing_vertices.LAST) := v;
    RETURN existing_vertices.LAST - 1; -- 0-indexed
  END add_vertex_if_new;

  -- Private function for creating nodes
  FUNCTION new_node_internal(
    p_node_id NUMBER,
    p_parent_id NUMBER,
    p_level_num NUMBER,
    p_is_leaf NUMBER,
    p_v_indices DBMS_SQL.NUMBER_TABLE -- Indices into g_vertices
  ) RETURN HTM_NODE IS
    node_children_ids DBMS_SQL.NUMBER_TABLE; -- Initially empty for new nodes
  BEGIN
    -- p_children_ids is empty for now, will be filled by make_new_layer
    RETURN HTM_NODE(
      node_id => p_node_id,
      parent_id => p_parent_id,
      level_num => p_level_num,
      is_leaf => p_is_leaf,
      children_ids => node_children_ids, 
      v_ids => p_v_indices,
      w_ids => NULL -- w_ids (midpoint vertex indices) are not directly stored in the node this way
    );
  END new_node_internal;

  -- Private procedure to build layers
  PROCEDURE make_new_layer(current_build_level NUMBER) IS
    parent_node HTM_NODE;
    parent_node_id NUMBER;
    child_node_id NUMBER;
    child_node HTM_NODE;
    
    v_indices DBMS_SQL.NUMBER_TABLE;
    v0 HTM_VECTOR;
    v1 HTM_VECTOR;
    v2 HTM_VECTOR;
    
    w0_vec HTM_VECTOR;
    w1_vec HTM_VECTOR;
    w2_vec HTM_VECTOR;
    w0_idx PLS_INTEGER;
    w1_idx PLS_INTEGER;
    w2_idx PLS_INTEGER;

    child_v_indices DBMS_SQL.NUMBER_TABLE := DBMS_SQL.NUMBER_TABLE(3);
    num_nodes_in_layer NUMBER := 0;
    num_new_vertices NUMBER := 0; -- Track new vertices for this layer
    
    current_layer_nodes HTM_NODE_LIST := HTM_NODE_LIST();
  BEGIN
    -- Collect all nodes from the current_build_level
    parent_node_id := g_nodes.FIRST;
    WHILE parent_node_id IS NOT NULL LOOP
        IF g_nodes(parent_node_id).level_num = current_build_level THEN
            current_layer_nodes.EXTEND;
            current_layer_nodes(current_layer_nodes.LAST) := g_nodes(parent_node_id);
        END IF;
        parent_node_id := g_nodes.NEXT(parent_node_id);
    END LOOP;

    IF current_layer_nodes.COUNT = 0 THEN
      RETURN; -- No nodes at this level to process
    END IF;

    FOR i IN 1 .. current_layer_nodes.COUNT LOOP
      parent_node := current_layer_nodes(i);
      parent_node_id := parent_node.node_id;

      -- Get parent vertices from g_vertices using indices from parent_node.v_ids
      v0 := g_vertices(parent_node.v_ids(1) + 1); -- v_ids are 0-indexed
      v1 := g_vertices(parent_node.v_ids(2) + 1);
      v2 := g_vertices(parent_node.v_ids(3) + 1);

      -- Calculate midpoints
      w0_vec := HTM_VECTOR((v1.x + v2.x)/2, (v1.y + v2.y)/2, (v1.z + v2.z)/2); w0_vec.normalize();
      w1_vec := HTM_VECTOR((v0.x + v2.x)/2, (v0.y + v2.y)/2, (v0.z + v2.z)/2); w1_vec.normalize();
      w2_vec := HTM_VECTOR((v0.x + v1.x)/2, (v0.y + v1.y)/2, (v0.z + v1.z)/2); w2_vec.normalize();

      -- Add midpoints to g_vertices if they are new, get their indices
      w0_idx := add_vertex_if_new(w0_vec, g_vertices);
      w1_idx := add_vertex_if_new(w1_vec, g_vertices);
      w2_idx := add_vertex_if_new(w2_vec, g_vertices);
      
      -- Update parent node to mark it as not a leaf and store children IDs
      g_nodes(parent_node_id).is_leaf := 0;
      g_nodes(parent_node_id).children_ids.DELETE; -- Clear if any old (shouldn't be)
      g_nodes(parent_node_id).children_ids.EXTEND(4);

      -- Create 4 child nodes
      FOR child_idx IN 0 .. 3 LOOP
        child_node_id := (parent_node_id * 4) + child_idx; -- Or (parent_node_id << 2) | child_idx

        CASE child_idx
          WHEN 0 THEN -- v0, w2, w1
            child_v_indices(1) := parent_node.v_ids(1); child_v_indices(2) := w2_idx; child_v_indices(3) := w1_idx;
          WHEN 1 THEN -- v1, w0, w2
            child_v_indices(1) := parent_node.v_ids(2); child_v_indices(2) := w0_idx; child_v_indices(3) := w2_idx;
          WHEN 2 THEN -- v2, w1, w0
            child_v_indices(1) := parent_node.v_ids(3); child_v_indices(2) := w1_idx; child_v_indices(3) := w0_idx;
          WHEN 3 THEN -- w0, w1, w2 (central triangle)
            child_v_indices(1) := w0_idx; child_v_indices(2) := w1_idx; child_v_indices(3) := w2_idx;
        END CASE;

        child_node := new_node_internal(
          p_node_id => child_node_id,
          p_parent_id => parent_node_id,
          p_level_num => current_build_level + 1,
          p_is_leaf => 1, -- Initially leaf, may become parent later
          p_v_indices => child_v_indices
        );
        g_nodes(child_node_id) := child_node;
        g_nodes(parent_node_id).children_ids(child_idx + 1) := child_node_id;
        num_nodes_in_layer := num_nodes_in_layer + 1;
      END LOOP;
    END LOOP;
    
    -- Update g_layers for the newly created layer
    g_layers.EXTEND;
    g_layers(g_layers.LAST) := HTM_LAYER_INFO(
      p_level_num => current_build_level + 1,
      p_n_nodes => num_nodes_in_layer,
      p_n_vertices => g_vertices.COUNT, -- Total vertices up to this layer
      p_n_edges => num_nodes_in_layer * 3, -- Each node has 3 edges
      p_first_node_id => (g_layers(g_layers.LAST-1).first_node_id * 4), -- Approximate, depends on ID scheme
      p_first_vertex_id => g_layers(g_layers.LAST-1).n_vertices -- Index of first new vertex for this layer
    );

  END make_new_layer;

  -- Public Procedures
  PROCEDURE initialize_htm(build_level NUMBER, query_level NUMBER) IS
    v_indices DBMS_SQL.NUMBER_TABLE := DBMS_SQL.NUMBER_TABLE(3);
    node_id NUMBER;
    
    -- Initial vertices of the octahedron (0-indexed for g_vertices)
    -- X+, X-, Y+, Y-, Z+, Z-
    v_data CONSTANT HTM_VERTEX_LIST := HTM_VERTEX_LIST(
      HTM_VECTOR(1, 0, 0), HTM_VECTOR(-1, 0, 0),
      HTM_VECTOR(0, 1, 0), HTM_VECTOR(0, -1, 0),
      HTM_VECTOR(0, 0, 1), HTM_VECTOR(0, 0, -1)
    );
    
    -- Initial 8 triangles (level 0)
    -- S0-S3 (IDs 8-11), N0-N3 (IDs 12-15)
    -- Vertex indices for each of the 8 base triangles (0-indexed referring to v_data)
    -- These are chosen to match the SpatialIndex.cpp orientation.
    -- S0: (0,5,3) -> v_data indices: X+, Z-, Y-
    -- S1: (3,5,1) -> Y-, Z-, X-
    -- S2: (1,5,2) -> X-, Z-, Y+
    -- S3: (2,5,0) -> Y+, Z-, X+
    -- N0: (0,2,4) -> X+, Y+, Z+
    -- N1: (2,1,4) -> Y+, X-, Z+
    -- N2: (1,3,4) -> X-, Y-, Z+
    -- N3: (3,0,4) -> Y-, X+, Z+
    TYPE base_triangle_def IS RECORD (id NUMBER, v_idx DBMS_SQL.NUMBER_TABLE);
    TYPE base_triangle_list IS TABLE OF base_triangle_def;
    initial_triangles CONSTANT base_triangle_list := base_triangle_list(
        base_triangle_def(8, DBMS_SQL.NUMBER_TABLE(0, 5, 3)), -- S0
        base_triangle_def(9, DBMS_SQL.NUMBER_TABLE(3, 5, 1)), -- S1
        base_triangle_def(10, DBMS_SQL.NUMBER_TABLE(1, 5, 2)),-- S2
        base_triangle_def(11, DBMS_SQL.NUMBER_TABLE(2, 5, 0)),-- S3
        base_triangle_def(12, DBMS_SQL.NUMBER_TABLE(0, 2, 4)),-- N0
        base_triangle_def(13, DBMS_SQL.NUMBER_TABLE(2, 1, 4)),-- N1
        base_triangle_def(14, DBMS_SQL.NUMBER_TABLE(1, 3, 4)),-- N2
        base_triangle_def(15, DBMS_SQL.NUMBER_TABLE(3, 0, 4)) -- N3
    );
    
  BEGIN
    g_max_build_level := build_level;
    g_max_query_level := query_level;

    g_nodes.DELETE;
    g_vertices.DELETE;
    g_layers.DELETE;

    -- Add initial 6 vertices to g_vertices
    FOR i IN 1 .. v_data.COUNT LOOP
      g_vertices.EXTEND;
      g_vertices(i) := v_data(i);
    END LOOP;

    -- Create the 8 base triangles (level 0)
    FOR i IN 1 .. initial_triangles.COUNT LOOP
      node_id := initial_triangles(i).id;
      v_indices := initial_triangles(i).v_idx;
      
      g_nodes(node_id) := new_node_internal(
        p_node_id => node_id,
        p_parent_id => 0, -- Root nodes have no parent, or use a sentinel like 0 or -1
        p_level_num => 0,
        p_is_leaf => CASE WHEN build_level = 0 THEN 1 ELSE 0 END,
        p_v_indices => v_indices
      );
    END LOOP;
    
    g_layers.EXTEND;
    g_layers(1) := HTM_LAYER_INFO(
      p_level_num => 0,
      p_n_nodes => 8,
      p_n_vertices => 6,
      p_n_edges => 8 * 3,
      p_first_node_id => 8, -- Smallest ID for level 0
      p_first_vertex_id => 0 -- First vertex index
    );

    -- Iteratively build layers up to g_max_build_level
    FOR l IN 0 .. g_max_build_level - 1 LOOP
      make_new_layer(l);
    END LOOP;

  END initialize_htm;

  PROCEDURE get_node_vertices(
    node_id NUMBER,
    v0 OUT HTM_VECTOR,
    v1 OUT HTM_VECTOR,
    v2 OUT HTM_VECTOR
  ) IS
    current_node HTM_NODE;
    current_node_id NUMBER := node_id;
    parent_node_id NUMBER;
    target_level NUMBER;
    current_level NUMBER;
    child_index_path DBMS_SQL.NUMBER_TABLE; -- Stores child indices from build_level to target_level
    
    temp_v0 HTM_VECTOR;
    temp_v1 HTM_VECTOR;
    temp_v2 HTM_VECTOR;
    child_vertices HTM_VERTEX_LIST;
  BEGIN
    IF g_nodes.EXISTS(node_id) AND g_nodes(node_id).level_num <= g_max_build_level THEN
      -- Node is pre-built
      current_node := g_nodes(node_id);
      v0 := g_vertices(current_node.v_ids(1) + 1);
      v1 := g_vertices(current_node.v_ids(2) + 1);
      v2 := g_vertices(current_node.v_ids(3) + 1);
    ELSE
      -- Node needs to be dynamically constructed
      target_level := HTM_GEOMETRY_UTILS.name_to_id(HTM_GEOMETRY_UTILS.id_to_name(node_id)); -- This is not right.
                                                                                            -- We need the level from the ID.
      -- A way to get level from ID:
      DECLARE
          name_rep VARCHAR2(100) := HTM_GEOMETRY_UTILS.id_to_name(node_id);
      BEGIN
          IF name_rep LIKE 'ID_TOO_SMALL' OR name_rep LIKE 'ID_OUT_OF_RANGE' THEN
            RAISE_APPLICATION_ERROR(-20002, 'Invalid node ID for level detection.');
          END IF;
          target_level := LENGTH(name_rep) - 1; -- 'N' or 'S' + digits for level
      END;


      IF target_level > g_max_query_level THEN
        RAISE_APPLICATION_ERROR(-20001, 'Node ID exceeds max query level.');
      END IF;

      -- Find ancestor at g_max_build_level
      current_level := target_level;
      parent_node_id := current_node_id;
      
      child_index_path.DELETE; -- Ensure it's empty

      WHILE current_level > g_max_build_level LOOP
        child_index_path(child_index_path.COUNT + 1) := MOD(parent_node_id, 4); -- Child index (0-3)
        parent_node_id := FLOOR(parent_node_id / 4);
        current_level := current_level - 1;
      END LOOP;

      -- Now parent_node_id is at g_max_build_level (or it's a root if target_level < g_max_build_level)
      IF NOT g_nodes.EXISTS(parent_node_id) THEN
         RAISE_APPLICATION_ERROR(-20003, 'Ancestor node at build level not found for ID: ' || node_id);
      END IF;
      
      current_node := g_nodes(parent_node_id);
      temp_v0 := g_vertices(current_node.v_ids(1) + 1);
      temp_v1 := g_vertices(current_node.v_ids(2) + 1);
      temp_v2 := g_vertices(current_node.v_ids(3) + 1);

      -- Iteratively apply get_triangle_vertices_from_parent
      -- Path is stored "backwards", so iterate from last to first
      FOR i IN REVERSE 1 .. child_index_path.COUNT LOOP
        child_vertices := HTM_GEOMETRY_UTILS.get_triangle_vertices_from_parent(
          temp_v0, temp_v1, temp_v2, child_index_path(i)
        );
        IF child_vertices IS NULL OR child_vertices.COUNT < 3 THEN
            RAISE_APPLICATION_ERROR(-20004, 'Failed to get child vertices dynamically for ID: ' || node_id);
        END IF;
        temp_v0 := child_vertices(1);
        temp_v1 := child_vertices(2);
        temp_v2 := child_vertices(3);
      END LOOP;
      
      v0 := temp_v0;
      v1 := temp_v1;
      v2 := temp_v2;
    END IF;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR(-20005, 'Node ID not found: ' || node_id);
    WHEN OTHERS THEN
      RAISE; -- Re-raise other exceptions
  END get_node_vertices;

  -- Public Functions
  FUNCTION get_node_info(node_id NUMBER) RETURN HTM_NODE IS
    node_level NUMBER;
    node_parent_id NUMBER;
    is_leaf_node NUMBER;
    node_name VARCHAR2(100);
    children DBMS_SQL.NUMBER_TABLE := DBMS_SQL.NUMBER_TABLE();
    v_ids_placeholder DBMS_SQL.NUMBER_TABLE := DBMS_SQL.NUMBER_TABLE(0,0,0); -- Placeholder, actual vertices via get_node_vertices
  BEGIN
    IF g_nodes.EXISTS(node_id) THEN
      RETURN g_nodes(node_id);
    ELSE
      -- Dynamically construct node info (mostly for level, parent, and potential children)
      node_name := HTM_GEOMETRY_UTILS.id_to_name(node_id);
      IF node_name LIKE 'ID_TOO_SMALL' OR node_name LIKE 'ID_OUT_OF_RANGE' THEN
        RAISE_APPLICATION_ERROR(-20010, 'Invalid node ID for dynamic info: ' || node_id);
      END IF;
      node_level := LENGTH(node_name) - 1;

      IF node_level = 0 THEN
        node_parent_id := 0; -- Root
      ELSE
        node_parent_id := FLOOR(node_id / 4);
      END IF;
      
      is_leaf_node := CASE WHEN node_level >= g_max_query_level THEN 1 ELSE 0 END;
      -- If not leaf, children could be calculated
      IF is_leaf_node = 0 THEN
        children.EXTEND(4);
        FOR i IN 0..3 LOOP
            children(i+1) := (node_id * 4) + i;
        END LOOP;
      END IF;

      RETURN HTM_NODE(
        node_id => node_id,
        parent_id => node_parent_id,
        level_num => node_level,
        is_leaf => is_leaf_node,
        children_ids => children,
        v_ids => v_ids_placeholder, -- Not accurate here, use get_node_vertices
        w_ids => NULL
      );
    END IF;
  END get_node_info;

  FUNCTION id_by_point(p HTM_VECTOR, target_level NUMBER) RETURN NUMBER IS
    current_node_id NUMBER;
    v0 HTM_VECTOR;
    v1 HTM_VECTOR;
    v2 HTM_VECTOR;
    child_vertices HTM_VERTEX_LIST;
    found_in_child BOOLEAN;
    
    -- Start with level 0 nodes (IDs 8-15)
    level0_ids DBMS_SQL.NUMBER_TABLE := DBMS_SQL.NUMBER_TABLE(8,9,10,11,12,13,14,15);
  BEGIN
    IF target_level < 0 OR target_level > g_max_query_level THEN
      RAISE_APPLICATION_ERROR(-20020, 'Target level out of range.');
    END IF;

    -- Find which level 0 triangle contains the point
    current_node_id := -1;
    FOR i IN 1 .. level0_ids.COUNT LOOP
      get_node_vertices(level0_ids(i), v0, v1, v2);
      IF HTM_GEOMETRY_UTILS.is_inside_triangle(p, v0, v1, v2) THEN
        current_node_id := level0_ids(i);
        EXIT;
      END IF;
    END LOOP;

    IF current_node_id = -1 THEN
      RAISE_APPLICATION_ERROR(-20021, 'Point not found in any level 0 triangle. Point: ' || p.to_string());
    END IF;

    -- Iteratively descend to target_level
    FOR current_level IN 0 .. target_level - 1 LOOP
      get_node_vertices(current_node_id, v0, v1, v2); -- Get vertices of current parent
      found_in_child := FALSE;
      FOR child_idx IN 0 .. 3 LOOP
        child_vertices := HTM_GEOMETRY_UTILS.get_triangle_vertices_from_parent(v0, v1, v2, child_idx);
        IF HTM_GEOMETRY_UTILS.is_inside_triangle(p, child_vertices(1), child_vertices(2), child_vertices(3)) THEN
          current_node_id := (current_node_id * 4) + child_idx;
          found_in_child := TRUE;
          EXIT;
        END IF;
      END LOOP;
      IF NOT found_in_child THEN
         -- This can happen due to precision issues at triangle boundaries.
         -- Default to child 0 or the "closest" if a more robust method is needed.
         -- For now, if it's not in any, it implies an issue or point exactly on an edge shared by deeper children.
         -- For simplicity, we can assume it must fall in one.
         -- A more robust solution might be needed if points on edges are common and problematic.
         -- One strategy is to pick the child whose center is closest to P, or the first one that contained it if multiple do (due to epsilon).
         RAISE_APPLICATION_ERROR(-20022, 'Point ' || p.to_string() || ' not found in any child of node ' || current_node_id || ' at level ' || current_level);
      END IF;
    END LOOP;

    RETURN current_node_id;
  END id_by_point;

  FUNCTION point_by_id(node_id NUMBER) RETURN HTM_VECTOR IS
    v0 HTM_VECTOR;
    v1 HTM_VECTOR;
    v2 HTM_VECTOR;
    center_vec HTM_VECTOR;
  BEGIN
    get_node_vertices(node_id, v0, v1, v2);
    center_vec := HTM_VECTOR(v0.x + v1.x + v2.x, v0.y + v1.y + v2.y, v0.z + v1.z + v2.z);
    center_vec.normalize();
    RETURN center_vec;
  END point_by_id;

END HTM_INDEX_CORE;
/
