CREATE OR REPLACE PACKAGE HTM_INDEX_CORE AS

  -- Publicly accessible global variables
  g_max_build_level NUMBER;
  g_max_query_level NUMBER;

  -- Public Procedures
  PROCEDURE initialize_htm(
    build_level NUMBER,
    query_level NUMBER
  );

  PROCEDURE get_node_vertices(
    node_id NUMBER,
    v0 OUT HTM_VECTOR,
    v1 OUT HTM_VECTOR,
    v2 OUT HTM_VECTOR
  );

  -- Public Functions
  FUNCTION get_node_info(
    node_id NUMBER
  ) RETURN HTM_NODE;

  FUNCTION id_by_point(
    p HTM_VECTOR,
    target_level NUMBER
  ) RETURN NUMBER;

  FUNCTION point_by_id(
    node_id NUMBER
  ) RETURN HTM_VECTOR;

  -- Potentially expose some global state for debugging or advanced use, if necessary
  -- For now, keep them internal to the package body.
  -- (The above comment is now slightly misleading as we are exposing some state,
  -- but the variables are fundamental to the package's configuration state)

END HTM_INDEX_CORE;
/
